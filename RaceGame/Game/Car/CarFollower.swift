import simd

/// Логика «машина едет за пальцем» + минимальная физика.
///
/// Палец оставляет след из точек, и в каждой точке запоминается скорость пальца. Машина
/// проезжает след до конца, стремясь ехать с той скоростью, с какой вели палец
/// (+ догоняет, если отстала). Но саму машину ограничивает физика:
/// - разгон слабеет с ростом скорости (сопротивление воздуха), максимум — `maxSpeed`;
/// - торможение ограничено `brakeDecel`;
/// - в повороте боковое ускорение не больше `grip`: на большой скорости радиус поворота
///   растёт, машину выносит наружу (недостаточная поворачиваемость), она скользит и теряет скорость;
/// - на траве сцепление хуже, и машина быстро теряет скорость.
/// Машина не едет точно по следу, а рулит к точке следа впереди (pure pursuit).
struct CarFollower {
    var position: SIMD2<Float>
    /// Направление движения (куда летит машина).
    private(set) var course: Float
    /// Направление кузова: при заносе отличается от `course`.
    private(set) var heading: Float
    private(set) var speed: Float = 0
    /// След, по которому едет машина, — сглаженная версия `rawPath`.
    private(set) var path: [SIMD2<Float>] = []
    /// Точки пальца как есть: дрожание руки делает линию волнистой, поэтому машина едет по `path`.
    private var rawPath: [SIMD2<Float>] = []
    /// Скорость пальца (м/с), записанная для каждой точки `path`.
    private var pathSpeeds: [Float] = []
    private(set) var steer: Float = 0
    private(set) var braking = false
    /// 0…1 — насколько машине не хватает сцепления, чтобы пройти поворот по следу.
    private(set) var slide: Float = 0
    /// Боковое ускорение в повороте, м/с².
    private(set) var lateralAccel: Float = 0

    private var liveFingerSpeed: Float = 0
    /// Слипстрим 0…1: в аэродинамическом следе машины впереди — до +10% к скорости и +6% к максимальной.
    var draft: Float = 0
    private var prevFinger: SIMD2<Float>?
    private var slipAngle: Float = 0

    // Ведение пальцем.
    let minSpeed: Float = 3             // м/с — минимальная скорость, чтобы след всегда доезжался
    let pointSpacing: Float = 0.5       // м между точками следа
    let followGap: Float = 2.5          // м — допустимое отставание; дальше машина догоняет
    let catchUpRate: Float = 6          // 1/с — прибавка скорости на каждый метр отставания сверх followGap
    let smoothRadius = 10               // точек (×pointSpacing = 5 м) в каждую сторону для сглаживания следа

    // Физика.
    private(set) var maxSpeed: Float = 350 / 3.6     // м/с
    private(set) var engineAccel: Float = 24         // м/с² на нулевой скорости, падает до 0 к maxSpeed
    let brakeDecel: Float = 45          // м/с²
    private(set) var grip: Float = 35                // м/с² — предельное боковое ускорение на асфальте (~3.5g)
    let grassGrip: Float = 12           // м/с² — на траве
    let grassDrag: Float = 25           // м/с² — дополнительное замедление на траве
    let grassMaxSpeed: Float = 20       // м/с — выше этой скорости трава тормозит
    let scrubDecel: Float = 18          // м/с² — потеря скорости при скольжении
    let wheelbase: Float = 2.34
    let maxSteer: Float = 0.4           // рад — максимальный угол поворота колёс

    /// `model` — машина из гаража: множители к разгону, максимальной скорости и сцеплению.
    init(position: SIMD2<Float>, heading: Float, model: CarModel = .standard) {
        self.position = position
        self.heading = heading
        self.course = heading
        maxSpeed *= model.topSpeed
        engineAccel *= model.acceleration
        grip *= model.grip
    }

    /// Сразу задать скорость — для старта с хода.
    mutating func launch(speed: Float) {
        self.speed = speed
    }

    /// Столкновение: машину сдвигает и она теряет скорость (не быстрее `limit`).
    mutating func bump(by offset: SIMD2<Float>, limit: Float) {
        position += offset
        speed = min(speed, max(limit, 0))
    }

    /// Новое касание начинает новый след.
    mutating func touchBegan(at p: SIMD2<Float>) {
        path = [p]
        rawPath = [p]
        pathSpeeds = [0]
        prevFinger = p
    }

    mutating func step(dt: Float, finger: SIMD2<Float>?, offTrack: Bool) {
        // 1. Текущая скорость пальца; дописываем след и скорость пальца на этом участке.
        if let f = finger, let prev = prevFinger {
            liveFingerSpeed += (simd_length(f - prev) / dt - liveFingerSpeed) * (1 - exp(-dt / 0.05))
        } else {
            liveFingerSpeed = 0
        }
        prevFinger = finger
        if let f = finger, simd_length(f - (rawPath.last ?? position)) >= pointSpacing {
            rawPath.append(f)
            path.append(f)
            pathSpeeds.append(min(liveFingerSpeed, maxSpeed))
            smoothTail()
        }
        dropPassedPoints()

        // 2. Целевая скорость (чего «хочет» игрок).
        let remaining = remainingPathLength()
        var target: Float = 0
        if let recorded = pathSpeeds.first {
            target = max(recorded, minSpeed) * (1 + 0.1 * draft) + catchUpRate * max(remaining - followGap, 0)
        }
        // Не проскакивать конец следа. Пока палец движется, конец следа уезжает вперёд.
        let lead = finger != nil ? liveFingerSpeed * 0.25 : 0
        let topSpeed = maxSpeed * (1 + 0.06 * draft)
        target = min(target, sqrt(2 * brakeDecel * max(remaining + lead - 0.5, 0)), topSpeed)

        // 3. Продольная динамика: мотор слабеет с ростом скорости, тормоза ограничены.
        let old = speed
        // Пока машину сносит, мотор не разгоняет её: скольжение гасит скорость,
        // пока поворот снова не станет проходимым.
        if slide > 0.15 { target = min(target, speed) }
        if target > speed {
            let accel = engineAccel * (1 + 0.4 * draft) * (1 - (speed / topSpeed) * (speed / topSpeed))
            speed += min(target - speed, accel * dt)
        } else {
            speed -= min(speed - target, brakeDecel * dt)
        }
        if offTrack && speed > grassMaxSpeed { speed -= grassDrag * dt }

        // 4. Руление к точке следа впереди с ограничением по сцеплению.
        var desiredYawRate: Float = 0
        let lookDistance = simd_clamp(4 + 0.12 * speed, 4, 16)
        if let aim = lookAhead(distance: lookDistance) {
            let d = aim - position
            let dist = simd_length(d)
            if dist > 0.3 {
                let alpha = wrapAngle(atan2(d.x, d.y) - course)
                let maxCurvature = tan(maxSteer) / wheelbase
                let curvature = simd_clamp(2 * sin(alpha) / max(dist, 1), -maxCurvature, maxCurvature)
                desiredYawRate = speed * curvature
            }
        }
        let maxYawRate = (offTrack ? grassGrip : grip) / max(speed, 0.5)
        let yawRate = simd_clamp(desiredYawRate, -maxYawRate, maxYawRate)
        let excess = abs(desiredYawRate) > maxYawRate ? min((abs(desiredYawRate) - maxYawRate) / maxYawRate, 1) : 0

        course = wrapAngle(course + yawRate * dt)
        lateralAccel = abs(yawRate * speed)
        position += SIMD2(sin(course), cos(course)) * speed * dt

        // 5. Скольжение: шины «трут», машина теряет скорость, кузов разворачивает в сторону поворота.
        speed = max(speed - excess * scrubDecel * dt, 0)
        slide += (excess - slide) * (1 - exp(-dt / 0.12))
        let slipTarget = (desiredYawRate >= 0 ? 1 : -1) * slide * 0.35
        slipAngle += (slipTarget - slipAngle) * (1 - exp(-dt / 0.15))
        heading = course + slipAngle

        braking = (speed - old) / dt < -6 || (speed < 0.5 && old > 0.5)

        // Колёса показывают, куда водитель хочет рулить (при сносе — больше, чем едет машина).
        let steerTarget = speed > 0.5 ? simd_clamp(atan(wheelbase * desiredYawRate / speed), -maxSteer, maxSteer) : steer
        steer += (steerTarget - steer) * (1 - exp(-dt / 0.08))
    }

    /// Убираем точки следа, которые машина уже проехала (или пролетела мимо при сносе).
    private mutating func dropPassedPoints() {
        while let first = path.first {
            let d0 = simd_length(first - position)
            let reached = d0 < max(1.5, speed * 0.05)
            let nextIsCloser = path.count >= 2 && simd_length(path[1] - position) <= d0
            guard reached || nextIsCloser else { break }
            path.removeFirst()
            rawPath.removeFirst()
            pathSpeeds.removeFirst()
        }
    }

    /// Сглаживание хвоста следа: каждая точка — взвешенное (треугольное окно) среднее соседей в пределах
    /// ±`smoothRadius`. У свежего конца соседей впереди ещё нет, и окно берёт только предыдущие точки:
    /// конец следа чуть (на 1–2 м) отстаёт от пальца, зато машина не виляет за дрожанием руки.
    /// По мере рисования точки получают соседей с обеих сторон и сглаживаются полностью.
    /// Крупные изгибы (повороты) сохраняются — убирается только мелкая волна.
    private mutating func smoothTail() {
        let n = rawPath.count
        for i in max(0, n - 1 - smoothRadius)..<n {
            var sum = SIMD2<Float>(repeating: 0)
            var weight: Float = 0
            for j in max(0, i - smoothRadius)...min(n - 1, i + smoothRadius) {
                let w = Float(smoothRadius + 1 - abs(j - i))
                sum += rawPath[j] * w
                weight += w
            }
            path[i] = sum / weight
        }
    }

    private func remainingPathLength() -> Float {
        var total: Float = 0
        var prev = position
        for p in path {
            total += simd_length(p - prev)
            prev = p
        }
        return total
    }

    private func lookAhead(distance: Float) -> SIMD2<Float>? {
        var left = distance
        var prev = position
        for p in path {
            let len = simd_length(p - prev)
            if len >= left { return prev + (p - prev) / len * left }
            left -= len
            prev = p
        }
        return path.last
    }
}
