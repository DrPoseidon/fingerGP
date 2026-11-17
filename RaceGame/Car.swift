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
    private let wind = Entity()
    private var windLines: [(entity: Entity, phase: Float)] = []
    private var windTime: Float = 0
    private var opacity: Float = 1
    private var wheelAngle: Float = 0
    private let tyreRadius: Float = 0.43
    /// Визуальный масштаб: модель в реальных метрах мелковата на экране телефона.
    let visualScale: Float

    /// Общая загрузка: одновременные вызовы ждут одну и ту же задачу, а не грузят модель повторно.
    @MainActor private static var templateTask: Task<Entity, Error>?

    /// Модель грузится асинхронно один раз, дальше — клонируется.
    /// `primary` — цвет вместо красного (кузов, понтоны, шлем), `secondary` — вместо белого (бока, крылья),
    /// `accent` — вместо синего (воздухозаборник, зеркала, закрылки); `model` — машина из гаража (размер крыльев).
    @MainActor
    static func load(scale: Float, primary: UIColor? = nil, secondary: UIColor? = nil, accent: UIColor? = nil,
                     model carModel: CarModel = .standard) async throws -> CarEntity {
        let task = templateTask ?? Task { try await Entity(named: "race_car") }
        templateTask = task
        do {
            let template = try await task.value
            let model = template.clone(recursive: true)
            recolor(model, primary: primary, secondary: secondary, accent: accent)
            scaleParts(of: model, prefix: "fw_", by: carModel.frontWing)
            scaleParts(of: model, prefix: "rw_", by: carModel.rearWing)
            return CarEntity(model: model, scale: scale)
        } catch {
            templateTask = nil
            throw error
        }
    }

    /// Перекрасить ливрею: красный материал — в `primary`, белый — в `secondary`, синий — в `accent`
    /// (материалы у клона свои, шаблон не меняется).
    @MainActor
    private static func recolor(_ entity: Entity, primary: UIColor?, secondary: UIColor?, accent: UIColor?) {
        guard primary != nil || secondary != nil || accent != nil else { return }
        if var model = entity.components[ModelComponent.self] {
            var changed = false
            model.materials = model.materials.map { material in
                guard var pbr = material as? PhysicallyBasedMaterial,
                      // Цвет из USD — в линейном RGB, getRed для него не срабатывает: компоненты читаются напрямую.
                      let c = pbr.baseColor.tint.cgColor.components, c.count >= 3 else { return material }
                let isRed = c[0] > 0.45 && c[1] < 0.3 && c[2] < 0.3
                let isNavy = c[2] > 0.5 && c[0] < 0.3 && c[1] < 0.35
                let isWhite = c[0] > 0.85 && c[1] > 0.85 && c[2] > 0.85
                guard let color = isRed ? primary : isWhite ? secondary : isNavy ? accent : nil else { return material }
                pbr.baseColor.tint = color
                changed = true
                return pbr
            }
            if changed { entity.components.set(model) }
        }
        for child in entity.children { recolor(child, primary: primary, secondary: secondary, accent: accent) }
    }

    /// Увеличить или уменьшить группу деталей (например, все части заднего крыла) вокруг её центра.
    @MainActor
    private static func scaleParts(of model: Entity, prefix: String, by factor: Float) {
        guard abs(factor - 1) > 0.01 else { return }
        var parts: [Entity] = []
        func collect(_ e: Entity) {
            if e.name.hasPrefix(prefix) { parts.append(e) }
            for child in e.children { collect(child) }
        }
        collect(model)
        guard let parent = parts.first?.parent else { return }
        let bounds = parts.map { $0.visualBounds(relativeTo: parent) }
        let lo = bounds.map(\.min).reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let hi = bounds.map(\.max).reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        // Крыло растёт вверх и в стороны от своего основания, а не от центра: не уходит под кузов.
        let pivot = SIMD3((lo.x + hi.x) / 2, lo.y, (lo.z + hi.z) / 2)
        for part in parts {
            part.scale *= factor
            part.position = pivot + (part.position - pivot) * factor
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
        wind.isEnabled = false
        root.addChild(wind)
        windLines = CarEntity.makeWindLines(in: wind)
    }

    /// Слипстрим: тонкие белые линии проносятся вдоль машины назад — струи воздуха.
    /// Простые неосвещаемые меши; прозрачность — общая, на родителе, так дёшево.
    private static func makeWindLines(in parent: Entity) -> [(entity: Entity, phase: Float)] {
        var material = UnlitMaterial(color: UIColor(red: 0.92, green: 0.98, blue: 1, alpha: 1))
        material.blending = .transparent(opacity: 0.8)
        let mesh = MeshResource.generateBox(width: 0.07, height: 0.02, depth: 2.6)
        // Линии по бокам машины и над ней, на разной высоте и со сдвигом по фазе.
        let slots: [(x: Float, y: Float)] = [(-1.6, 0.5), (-1.9, 0.9), (-1.3, 1.2), (1.6, 0.5), (1.9, 0.9), (1.3, 1.2), (-0.5, 1.5), (0.5, 1.4)]
        return slots.enumerated().map { i, slot in
            let line = ModelEntity(mesh: mesh, materials: [material])
            line.position = [slot.x, slot.y, 0]
            parent.addChild(line)
            return (line, Float(i) * 0.37)
        }
    }

    /// Сила слипстрима 0…1: линии видны и бегут назад, сильнее — ярче.
    func updateWind(draft: Float, dt: Float) {
        guard draft > 0.05 else {
            if wind.isEnabled { wind.isEnabled = false }
            return
        }
        wind.isEnabled = true
        wind.components.set(OpacityComponent(opacity: min(0.25 + draft, 1)))
        // Линия пролетает от носа (z = 3) к хвосту (z = −4) за ~0.35 с и появляется снова.
        windTime += dt / 0.35
        for (entity, phase) in windLines {
            let k = (windTime + phase).truncatingRemainder(dividingBy: 1)
            entity.position.z = 3 - 7 * k
        }
    }

    /// Полупрозрачность (соперник, сквозь которого проезжает игрок). 1 — обычная машина.
    /// Прозрачность дорогая (124 детали в прозрачном проходе), поэтому включается только на время касания.
    func setOpacity(_ value: Float) {
        guard abs(value - opacity) > 0.01 || (value == 1 && opacity != 1) else { return }
        opacity = value
        if value >= 0.999 {
            root.components.remove(OpacityComponent.self)
        } else {
            root.components.set(OpacityComponent(opacity: value))
        }
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

func wrapAngle(_ a: Float) -> Float {
    var a = a.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi }
    if a < -.pi { a += 2 * .pi }
    return a
}
