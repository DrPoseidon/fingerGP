import RealityKit
import UIKit
import simd

/// Визуальная часть машины: модель, вращение колёс, руль, стоп-сигнал.
/// Модель смотрит в +Z, поэтому курс `heading` задаётся так, что «вперёд» = (sin h, 0, cos h).
final class CarEntity {
    let root = Entity()
    private let wheels: [Entity]
    private let frontWheels: [Entity]
    private let brakeOn: Entity?
    private let exhaust = Entity()
    private let tyreSmoke: [Entity]
    private var wheelAngle: Float = 0
    private let tyreRadius: Float = 0.43
    /// Визуальный масштаб: модель в реальных метрах мелковата на экране телефона.
    let visualScale: Float

    /// Общая загрузка: одновременные вызовы ждут одну и ту же задачу, а не грузят модель повторно.
    @MainActor private static var templateTask: Task<Entity, Error>?

    /// Модель грузится асинхронно один раз, дальше — клонируется.
    @MainActor
    static func load(scale: Float) async throws -> CarEntity {
        let task = templateTask ?? Task { try await Entity(named: "race_car") }
        templateTask = task
        do {
            let template = try await task.value
            return CarEntity(model: template.clone(recursive: true), scale: scale)
        } catch {
            templateTask = nil
            throw error
        }
    }

    private init(model: Entity, scale: Float) {
        visualScale = scale
        root.addChild(model)
        root.scale = SIMD3(repeating: scale)
        wheels = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"].compactMap { model.findEntity(named: $0) }
        frontWheels = ["wheel_FL", "wheel_FR"].compactMap { model.findEntity(named: $0) }
        brakeOn = model.findEntity(named: "rain_light_leds_on")
        brakeOn?.isEnabled = false

        // Эффекты — в координатах модели (метры, нос в +Z), масштабируются вместе с машиной.
        exhaust.position = [0, 0.42, -1.95]
        exhaust.components.set(CarEntity.makeExhaust())
        root.addChild(exhaust)
        tyreSmoke = [Float(0.88), -0.88].map { x in
            let e = Entity()
            e.position = [x, 0.1, -1.35]
            e.components.set(CarEntity.makeTyreSmoke())
            return e
        }
        for e in tyreSmoke { root.addChild(e) }
    }

    /// Выхлоп: лёгкая сизая дымка, гуще при разгоне.
    private static func makeExhaust() -> ParticleEmitterComponent {
        var p = ParticleEmitterComponent()
        p.emitterShape = .sphere
        p.emitterShapeSize = [0.05, 0.05, 0.05]
        p.particlesInheritTransform = false
        p.emissionDirection = [0, 0.3, -1]
        p.speed = 1.2
        p.speedVariation = 0.4
        p.mainEmitter.birthRate = 0
        p.mainEmitter.lifeSpan = 0.45
        p.mainEmitter.lifeSpanVariation = 0.1
        p.mainEmitter.size = 0.12
        p.mainEmitter.sizeVariation = 0.03
        p.mainEmitter.sizeMultiplierAtEndOfLifespan = 4
        p.mainEmitter.spreadingAngle = 0.25
        p.mainEmitter.acceleration = [0, 0.6, 0]
        p.mainEmitter.dampingFactor = 2
        p.mainEmitter.color = .evolving(start: .single(UIColor(white: 0.55, alpha: 0.35)),
                                        end: .single(UIColor(white: 0.75, alpha: 0)))
        p.mainEmitter.opacityCurve = .linearFadeOut
        p.mainEmitter.blendMode = .alpha
        return p
    }

    /// Дым из-под задних колёс: белые клубы, остаются висеть позади машины.
    private static func makeTyreSmoke() -> ParticleEmitterComponent {
        var p = ParticleEmitterComponent()
        p.emitterShape = .sphere
        p.emitterShapeSize = [0.2, 0.05, 0.2]
        p.particlesInheritTransform = false
        p.emissionDirection = [0, 1, 0]
        p.speed = 0.6
        p.speedVariation = 0.3
        p.mainEmitter.birthRate = 0
        p.mainEmitter.lifeSpan = 1.4
        p.mainEmitter.lifeSpanVariation = 0.4
        p.mainEmitter.size = 0.35
        p.mainEmitter.sizeVariation = 0.1
        p.mainEmitter.sizeMultiplierAtEndOfLifespan = 5
        p.mainEmitter.spreadingAngle = 0.8
        p.mainEmitter.acceleration = [0, 0.3, 0]
        p.mainEmitter.dampingFactor = 1.5
        p.mainEmitter.color = .evolving(start: .single(UIColor(white: 0.95, alpha: 0.55)),
                                        end: .single(UIColor(white: 0.85, alpha: 0)))
        p.mainEmitter.opacityCurve = .easeFadeOut
        p.mainEmitter.blendMode = .alpha
        return p
    }

    /// `throttle` 0…1 — насколько машина разгоняется; `smoke` 0…1 — сила дыма из-под колёс.
    func updateEffects(speed: Float, throttle: Float, smoke: Float) {
        if var p = exhaust.components[ParticleEmitterComponent.self] {
            p.mainEmitter.birthRate = speed < 0.3 && throttle == 0 ? 6 : 14 + 50 * throttle
            exhaust.components.set(p)
        }
        for e in tyreSmoke {
            guard var p = e.components[ParticleEmitterComponent.self] else { continue }
            p.mainEmitter.birthRate = smoke > 0.02 ? 25 + 90 * smoke : 0
            e.components.set(p)
        }
    }

    func update(position: SIMD2<Float>, heading: Float, speed: Float, steer: Float, braking: Bool, dt: Float) {
        root.position = SIMD3(position.x, 0, position.y)
        root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])

        wheelAngle = (wheelAngle + speed / (tyreRadius * visualScale) * dt).truncatingRemainder(dividingBy: 2 * .pi)
        let roll = simd_quatf(angle: wheelAngle, axis: [1, 0, 0])
        let yaw = simd_quatf(angle: steer, axis: [0, 1, 0])
        for w in wheels {
            w.orientation = frontWheels.contains { $0 === w } ? yaw * roll : roll
        }
        brakeOn?.isEnabled = braking
    }
}

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
    private var prevFinger: SIMD2<Float>?
    private var slipAngle: Float = 0

    // Ведение пальцем.
    let minSpeed: Float = 3             // м/с — минимальная скорость, чтобы след всегда доезжался
    let pointSpacing: Float = 0.5       // м между точками следа
    let followGap: Float = 2.5          // м — допустимое отставание; дальше машина догоняет
    let catchUpRate: Float = 6          // 1/с — прибавка скорости на каждый метр отставания сверх followGap
    let smoothRadius = 10               // точек (×pointSpacing = 5 м) в каждую сторону для сглаживания следа

    // Физика.
    let maxSpeed: Float = 350 / 3.6     // м/с
    let engineAccel: Float = 24         // м/с² на нулевой скорости, падает до 0 к maxSpeed
    let brakeDecel: Float = 45          // м/с²
    let grip: Float = 35                // м/с² — предельное боковое ускорение на асфальте (~3.5g)
    let grassGrip: Float = 12           // м/с² — на траве
    let grassDrag: Float = 25           // м/с² — дополнительное замедление на траве
    let grassMaxSpeed: Float = 20       // м/с — выше этой скорости трава тормозит
    let scrubDecel: Float = 18          // м/с² — потеря скорости при скольжении
    let wheelbase: Float = 2.34
    let maxSteer: Float = 0.4           // рад — максимальный угол поворота колёс

    init(position: SIMD2<Float>, heading: Float) {
        self.position = position
        self.heading = heading
        self.course = heading
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
            target = max(recorded, minSpeed) + catchUpRate * max(remaining - followGap, 0)
        }
        // Не проскакивать конец следа. Пока палец движется, конец следа уезжает вперёд.
        let lead = finger != nil ? liveFingerSpeed * 0.25 : 0
        target = min(target, sqrt(2 * brakeDecel * max(remaining + lead - 0.5, 0)), maxSpeed)

        // 3. Продольная динамика: мотор слабеет с ростом скорости, тормоза ограничены.
        let old = speed
        // Пока машину сносит, мотор не разгоняет её: скольжение гасит скорость,
        // пока поворот снова не станет проходимым.
        if slide > 0.15 { target = min(target, speed) }
        if target > speed {
            let accel = engineAccel * (1 - (speed / maxSpeed) * (speed / maxSpeed))
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

func wrapAngle(_ a: Float) -> Float {
    var a = a.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi }
    if a < -.pi { a += 2 * .pi }
    return a
}
