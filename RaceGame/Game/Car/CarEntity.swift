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
    private var windOpacity: Float = 0
    private let detail: Detail
    private var exhaustRate: Float = -1
    private var smokeRate: Float = -1
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
    /// `detail: .reduced` — облегчённая машина для соперников: без мелких деталей, тени и выхлопа.
    static func load(scale: Float, primary: UIColor? = nil, secondary: UIColor? = nil, accent: UIColor? = nil,
                     model carModel: CarModel = .standard, detail: Detail = .full) async throws -> CarEntity {
        let task = templateTask ?? Task { try await Entity(named: "race_car") }
        templateTask = task
        do {
            let template = try await task.value
            let model = template.clone(recursive: true)
            recolor(model, primary: primary, secondary: secondary, accent: accent)
            scaleParts(of: model, prefix: "fw_", by: carModel.frontWing)
            scaleParts(of: model, prefix: "rw_", by: carModel.rearWing)
            if detail == .reduced { reduce(model) }
            return CarEntity(model: model, scale: scale, detail: detail)
        } catch {
            templateTask = nil
            throw error
        }
    }

    enum Detail { case full, reduced }

    /// Детали, которых сверху с высоты камеры не видно, а рисовать их дорого: шлем и дуга безопасности —
    /// по 11–12 тыс. треугольников, мелочи (подвеска, детали колёс, зеркала) — десятки отдельных вызовов отрисовки.
    private static let hiddenInReducedModel = ["halo_", "visor", "headrest", "susp_", "driveshaft_",
                                               "mirror", "diff_strake", "tcam", "rain_light", "shark_fin",
                                               "floor_edge", "_rim_lip", "_brake_drum", "wheel_FL_inner",
                                               "wheel_FR_inner", "wheel_RL_inner", "wheel_RR_inner", "_stripe_",
                                               "_inlet_", "airbox_inlet", "beam_wing"]

    /// Облегчить модель: скрыть мелкие детали, шлем заменить простой сферой того же цвета, убрать тени.
    @MainActor
    private static func reduce(_ model: Entity) {
        func visit(_ e: Entity) {
            if hiddenInReducedModel.contains(where: { e.name.contains($0) }) {
                e.isEnabled = false
                return
            }
            if e.name == "helmet", let component = e.components[ModelComponent.self] {
                let bounds = e.visualBounds(relativeTo: e)
                let sphere = ModelEntity(mesh: .generateSphere(radius: bounds.extents.max() / 2),
                                         materials: component.materials.prefix(1).map { $0 })
                sphere.position = bounds.center
                sphere.components.set(DynamicLightShadowComponent(castsShadow: false))
                e.addChild(sphere)
                e.components.remove(ModelComponent.self)
            }
            if e.components.has(ModelComponent.self) {
                e.components.set(DynamicLightShadowComponent(castsShadow: false))
            }
            for child in e.children { visit(child) }
        }
        visit(model)
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

    private init(model: Entity, scale: Float, detail: Detail) {
        self.detail = detail
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
        // Прозрачность меняется ступенями — компонент не пересоздаётся каждый кадр.
        let opacity = (min(0.25 + draft, 1) * 10).rounded() / 10
        if opacity != windOpacity {
            windOpacity = opacity
            wind.components.set(OpacityComponent(opacity: opacity))
        }
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
        p.mainEmitter.lifeSpan = 1.0
        p.mainEmitter.lifeSpanVariation = 0.3
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
    /// Частицы — главный расход GPU (полупрозрачные слои перекрывают друг друга), поэтому их немного,
    /// у соперников — ещё меньше, а эмиттеры обновляются, только когда интенсивность заметно меняется.
    func updateEffects(speed: Float, throttle: Float, smoke: Float) {
        let exhaustTarget: Float = detail == .reduced ? 0 : speed < 0.3 && throttle == 0 ? 6 : 14 + 40 * throttle
        if abs(exhaustTarget - exhaustRate) > 4 || (exhaustTarget == 0) != (exhaustRate == 0) {
            exhaustRate = exhaustTarget
            if var p = exhaust.components[ParticleEmitterComponent.self] {
                p.mainEmitter.birthRate = exhaustTarget
                exhaust.components.set(p)
            }
        }
        let maxSmoke: Float = detail == .reduced ? 30 : 60
        let smokeTarget: Float = smoke > 0.02 ? maxSmoke * (0.25 + 0.75 * smoke) : 0
        if abs(smokeTarget - smokeRate) > 4 || (smokeTarget == 0) != (smokeRate == 0) {
            smokeRate = smokeTarget
            for e in tyreSmoke {
                guard var p = e.components[ParticleEmitterComponent.self] else { continue }
                p.mainEmitter.birthRate = smokeTarget
                e.components.set(p)
            }
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
