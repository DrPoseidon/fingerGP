import Metal
import RealityKit
import UIKit
import simd

/// Город и порт («Гавань»): кварталы домов вокруг трассы, скверы, фонари вдоль трассы,
/// вдоль стартовой прямой — набережная, у её концов — порт с контейнерами и кранами.
@MainActor
extension Track {
    func addCity(_ builder: SceneryBuilder) {
        let s = propScale
        let minP = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let maxP = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        // Набережная — сразу за стартовой прямой (она у самого «южного» края трассы), чтобы вода была в кадре.
        let quayZ = maxP.y + halfWidth + curbWidth + 16 * s
        var rng = SeededRandom(seed: 0xC17)

        addWater(builder, quayZ: quayZ, from: minP.x - 600, to: maxP.x + 600)
        addStreetLights(builder)
        addFrontage(builder, portZ: maxP.y, quayZ: quayZ, rng: &rng)
        addPort(builder, from: maxP.y, quayZ: quayZ, minX: minP.x - 250, maxX: maxP.x + 250, rng: &rng)
        addBlocks(builder, min: minP - 260, max: SIMD2(maxP.x + 260, maxP.y), portZ: maxP.y, rng: &rng)
        addInfill(builder, min: minP - 60, max: SIMD2(maxP.x + 60, maxP.y), rng: &rng)
    }

    private var propScale: Float { definition.carScale / 1.5 }

    private func ground(_ p: SIMD2<Float>, _ y: Float = 0) -> SIMD3<Float> { SIMD3(p.x, y, p.y) }

    /// Сколько свободного места от точки до края поребрика ближайшего участка трассы.
    private func clearance(_ p: SIMD2<Float>) -> Float { approximateDistance(p) - halfWidth - curbWidth }

    // MARK: - Материалы

    private static func plain(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, roughness: Float = 0.9) -> RealityKit.Material {
        SimpleMaterial(color: UIColor(red: r, green: g, blue: b, alpha: 1), roughness: .init(floatLiteral: roughness), isMetallic: false)
    }

    /// Материал с повторяющейся текстурой (окна, рёбра контейнеров), окрашенной в `tint`.
    private static func tiled(_ texture: TextureResource?, tint: UIColor) -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.roughness = .init(floatLiteral: 0.85)
        guard let texture else {
            material.baseColor = .init(tint: tint)
            return material
        }
        let sampler = MTLSamplerDescriptor()
        sampler.sAddressMode = .repeat
        sampler.tAddressMode = .repeat
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear
        material.baseColor = .init(tint: tint, texture: .init(texture, sampler: .init(sampler)))
        return material
    }

    private static func texture(size: CGSize, draw: (CGContext) -> Void) -> TextureResource? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        guard let cg = image.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
    }

    /// Клетка фасада: светлая стена и окно (одна клетка — окно одного этажа).
    private static let windowTexture = texture(size: CGSize(width: 64, height: 64)) { cg in
        UIColor(white: 1, alpha: 1).setFill()
        cg.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        UIColor(red: 0.22, green: 0.3, blue: 0.4, alpha: 1).setFill()
        cg.fill(CGRect(x: 14, y: 16, width: 36, height: 34))
        UIColor(red: 0.45, green: 0.58, blue: 0.7, alpha: 1).setFill()
        cg.fill(CGRect(x: 14, y: 16, width: 36, height: 9))
    }

    /// Гофрированная стенка контейнера: вертикальные рёбра.
    private static let ribTexture = texture(size: CGSize(width: 32, height: 8)) { cg in
        UIColor.white.setFill()
        cg.fill(CGRect(x: 0, y: 0, width: 32, height: 8))
        UIColor(white: 0.72, alpha: 1).setFill()
        for x in stride(from: 0, to: 32, by: 8) { cg.fill(CGRect(x: x, y: 0, width: 3, height: 8)) }
    }

    private static let facades: [UIColor] = [
        UIColor(red: 0.93, green: 0.88, blue: 0.78, alpha: 1), UIColor(red: 0.85, green: 0.6, blue: 0.45, alpha: 1),
        UIColor(red: 0.8, green: 0.82, blue: 0.84, alpha: 1), UIColor(red: 0.66, green: 0.76, blue: 0.86, alpha: 1),
        UIColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1), UIColor(red: 0.74, green: 0.5, blue: 0.42, alpha: 1),
    ]

    private static let containerColors: [UIColor] = [
        UIColor(red: 0.8, green: 0.2, blue: 0.15, alpha: 1), UIColor(red: 0.15, green: 0.35, blue: 0.7, alpha: 1),
        UIColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1), UIColor(red: 0.2, green: 0.55, blue: 0.35, alpha: 1),
        UIColor(red: 0.6, green: 0.62, blue: 0.64, alpha: 1), UIColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1),
    ]

    // MARK: - Кварталы

    /// Сетка кварталов: в каждой клетке — дом или (иногда) сквер. Чем ближе к трассе, тем ниже дома,
    /// чтобы с высокой камеры они не закрывали трассу; вдали — высотки.
    private func addBlocks(_ builder: SceneryBuilder, min lo: SIMD2<Float>, max hi: SIMD2<Float>, portZ: Float,
                           rng: inout SeededRandom) {
        let s = propScale
        let pitch = 38 * s, floor = 3.6 * s
        for (k, color) in Self.facades.enumerated() {
            builder.material("facade.\(k)") { Self.tiled(Self.windowTexture, tint: color) }
        }
        builder.material("roof") { Self.plain(0.38, 0.38, 0.4) }
        builder.material("roof.unit") { Self.plain(0.7, 0.7, 0.72) }
        builder.material("park") { Self.plain(0.36, 0.6, 0.3, roughness: 1) }

        var z = lo.y
        while z < hi.y {
            var x = lo.x
            while x < hi.x {
                defer { x += pitch }
                let c = SIMD2(x + pitch / 2 + rng.next(in: -3...3), z + pitch / 2 + rng.next(in: -3...3))
                let size = SIMD2(rng.next(in: 0.6...0.88), rng.next(in: 0.6...0.88)) * pitch
                let park = rng.next(in: 0...1) < 0.1
                let tall = rng.next(in: 0...1), color = Int(rng.next(in: 0...0.999) * Float(Self.facades.count))
                let unit = rng.next(in: 0...1) < 0.5
                guard c.y + size.y / 2 < portZ else { continue }
                let radius = simd_length(size) / 2
                // Свободное место — по углам и серединам сторон участка (круг вокруг него отодвигал бы дома
                // слишком далеко от трассы).
                let probes = [-0.5, 0, 0.5].flatMap { u in [-0.5, 0, 0.5].map { v in c + SIMD2<Float>(Float(u), Float(v)) * size } }
                let room = probes.map(clearance).min() ?? 0
                guard room > 3 * s, builder.isFree(c, radius: radius) else { continue }
                builder.reserve(c, radius: radius)
                if park {
                    addPark(builder, center: c, size: size, rng: &rng)
                    continue
                }
                // Высота: у самой трассы — 2 этажа, дальше растёт; самые дальние — до 25 этажей.
                let limit = max(2 * floor, 4 * s + room * 0.7)
                let floors = Int(min(limit, (8 + tall * tall * 82) * s) / floor)
                let height = Float(max(floors, 2)) * floor
                addBuilding(builder, center: c, size: size, height: height, color: color, roofUnit: unit)
            }
            z += pitch
        }
    }

    /// Дом: коробка с окнами, плоская крыша и иногда блок вентиляции на ней. `right` — направление длинной стороны.
    private func addBuilding(_ builder: SceneryBuilder, center c: SIMD2<Float>, size: SIMD2<Float>, height: Float,
                             color: Int, roofUnit: Bool, right: SIMD2<Float> = [1, 0]) {
        let s = propScale
        let r = SIMD3(right.x, 0, right.y), f = SIMD3(-right.y, 0, right.x)
        builder.add("facade.\(color)", at: c) {
            $0.box(center: ground(c, height / 2), size: SIMD3(size.x, height, size.y), right: r, forward: f,
                   tile: SIMD2(4 * s, 3.6 * s))
        }
        builder.add("roof", at: c) {
            $0.box(center: ground(c, height + 0.3 * s), size: SIMD3(size.x - 1.5 * s, 0.6 * s, size.y - 1.5 * s), right: r, forward: f)
        }
        if roofUnit {
            let p = c + right * size.x * 0.15 + SIMD2(-right.y, right.x) * size.y * 0.15
            builder.add("roof.unit", at: c) {
                $0.box(center: ground(p, height + 1.6 * s), size: SIMD3(6 * s, 2.4 * s, 4 * s), right: r, forward: f)
            }
        }
    }

    /// Ряд невысоких домов вдоль трассы с обеих сторон, развёрнутых по её направлению, — «городская трасса».
    private func addFrontage(_ builder: SceneryBuilder, portZ: Float, quayZ: Float, rng: inout SeededRandom) {
        let s = propScale
        builder.material("warehouse") { Self.tiled(Self.ribTexture, tint: UIColor(red: 0.42, green: 0.5, blue: 0.58, alpha: 1)) }
        builder.material("warehouse.roof") { Self.plain(0.58, 0.6, 0.62) }
        for side: Float in [-1, 1] {
            var along: Float = 0
            while along < length {
                let width = rng.next(in: 22...38) * s, depth = rng.next(in: 14...22) * s
                let setback = rng.next(in: 7...12) * s
                let floors = Int(rng.next(in: 2...5.99)), color = Int(rng.next(in: 0...0.999) * Float(Self.facades.count))
                let unit = rng.next(in: 0...1) < 0.4
                let gap = rng.next(in: 0...1) < 0.2 ? 30 * s : rng.next(in: 3...8) * s
                defer { along += width + gap }
                let (p, t) = frame(atDistance: along + width / 2)
                let nrm = SIMD2(t.y, -t.x) * side
                let c = p + nrm * (halfWidth + curbWidth + setback + depth / 2)
                // Со стороны порта вдоль трассы — длинные низкие склады.
                let warehouse = c.y + depth > portZ
                let probes = [-0.5, 0, 0.5].flatMap { u in [-0.5, 0.5].map { v in c + t * Float(u) * width + nrm * Float(v) * depth } }
                guard probes.allSatisfy({ clearance($0) > 4 * s && $0.y < quayZ - 4 * s }),
                      builder.isFree(c, radius: min(width, depth) / 2) else { continue }
                builder.reserve(c, radius: max(width, depth) / 2)
                if warehouse {
                    builder.add("warehouse", at: c) {
                        $0.box(center: ground(c, 4 * s), size: SIMD3(width, 8 * s, depth), right: SIMD3(t.x, 0, t.y),
                               forward: SIMD3(nrm.x, 0, nrm.y), tile: SIMD2(6 * s, 8 * s))
                    }
                    builder.add("warehouse.roof", at: c) {
                        $0.box(center: ground(c, 8.2 * s), size: SIMD3(width - 0.6 * s, 0.4 * s, depth - 0.6 * s),
                               right: SIMD3(t.x, 0, t.y), forward: SIMD3(nrm.x, 0, nrm.y))
                    }
                    continue
                }
                addBuilding(builder, center: c, size: SIMD2(width, depth), height: Float(floors) * 3.6 * s,
                            color: color, roofUnit: unit, right: t)
            }
        }
    }

    /// Просветы, куда не влезли кварталы (внутри связок поворотов), — небольшие дома и группы деревьев.
    private func addInfill(_ builder: SceneryBuilder, min lo: SIMD2<Float>, max hi: SIMD2<Float>, rng: inout SeededRandom) {
        let s = propScale
        for _ in 0..<1500 {
            let c = SIMD2(rng.next(in: lo.x...hi.x), rng.next(in: lo.y...hi.y))
            let size = SIMD2(rng.next(in: 12...22), rng.next(in: 12...22)) * s
            let trees = rng.next(in: 0...1) < 0.3
            let floors = Int(rng.next(in: 2...3.99)), color = Int(rng.next(in: 0...0.999) * Float(Self.facades.count))
            let radius = simd_length(size) / 2
            let probes = [-0.5, 0.5].flatMap { u in [-0.5, 0.5].map { v in c + SIMD2<Float>(Float(u), Float(v)) * size } } + [c]
            guard probes.allSatisfy({ clearance($0) > 4 * s }), builder.isFree(c, radius: radius) else { continue }
            builder.reserve(c, radius: radius)
            if trees {
                for _ in 0..<3 {
                    let p = c + SIMD2(rng.next(in: -0.4...0.4), rng.next(in: -0.4...0.4)) * size
                    addTree(builder, at: p, scale: rng.next(in: 0.8...1.2) * s, conifer: false,
                            shade: rng.next(in: 0...1) < 0.5, phase: rng.next(in: 0...6))
                }
            } else {
                addBuilding(builder, center: c, size: size, height: Float(floors) * 3.6 * s, color: color, roofUnit: false)
            }
        }
    }

    private func addPark(_ builder: SceneryBuilder, center c: SIMD2<Float>, size: SIMD2<Float>, rng: inout SeededRandom) {
        let s = propScale
        builder.add("park", at: c) {
            $0.quad(ground(c + SIMD2(-size.x, -size.y) / 2, 0.03), ground(c + SIMD2(size.x, -size.y) / 2, 0.03),
                    ground(c + size / 2, 0.03), ground(c + SIMD2(-size.x, size.y) / 2, 0.03), facing: [0, 1, 0])
        }
        for _ in 0..<5 {
            let p = c + SIMD2(rng.next(in: -0.35...0.35) * size.x, rng.next(in: -0.35...0.35) * size.y)
            let scale = rng.next(in: 0.8...1.2) * s, shade = rng.next(in: 0...1) < 0.5, phase = rng.next(in: 0...6)
            addTree(builder, at: p, scale: scale, conifer: false, shade: shade, phase: phase)
        }
    }

    // MARK: - Фонари

    /// Фонари вдоль трассы с обеих сторон через 45 м, кронштейном к трассе.
    private func addStreetLights(_ builder: SceneryBuilder) {
        let s = propScale
        builder.material("lamp") { UnlitMaterial(color: UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)) }
        let every = Int(45 * s / step)
        for (k, i) in stride(from: 0, to: points.count, by: every).enumerated() {
            let side: Float = k % 2 == 0 ? 1 : -1
            let nrm = normals[i] * side
            let foot = points[i] + nrm * (halfWidth + curbWidth + 2.5 * s)
            guard clearance(foot) > 0, builder.isFree(foot, radius: 1.5 * s) else { continue }
            builder.reserve(foot, radius: 1.5 * s)
            let height = 7 * s
            let toTrack = SIMD3(-nrm.x, 0, -nrm.y)
            let arm = ground(foot, height) + toTrack * 1.4 * s
            builder.add("post", at: foot) {
                $0.prism(base: ground(foot), radius: 0.16 * s, height: height, sides: 5)
                $0.box(center: arm, size: SIMD3(0.25 * s, 0.25 * s, 2.8 * s),
                       right: simd_cross([0, 1, 0], toTrack), forward: toTrack)
            }
            builder.add("lamp", at: foot) {
                $0.box(center: arm + toTrack * 1.4 * s - SIMD3(0, 0.2 * s, 0), size: SIMD3(0.6 * s, 0.25 * s, 1.2 * s),
                       right: simd_cross([0, 1, 0], toTrack), forward: toTrack)
            }
        }
    }

    // MARK: - Порт и вода

    private func addWater(_ builder: SceneryBuilder, quayZ: Float, from x0: Float, to x1: Float) {
        let s = propScale
        builder.material("water") {
            SimpleMaterial(color: UIColor(red: 0.16, green: 0.42, blue: 0.62, alpha: 1), roughness: 0.15, isMetallic: false)
        }
        builder.material("quay") { Self.plain(0.5, 0.5, 0.5) }
        let far = quayZ + 1500
        // Вода — полосами по 300 м, чтобы каждый кусок попадал в свой квадрат и отсекался вне кадра.
        for x in stride(from: x0, to: x1, by: 300) {
            let x2 = min(x + 300, x1)
            builder.add("water", at: SIMD2((x + x2) / 2, quayZ + 10)) {
                $0.quad(SIMD3(x, 0.03, quayZ), SIMD3(x2, 0.03, quayZ), SIMD3(x2, 0.03, far), SIMD3(x, 0.03, far), facing: [0, 1, 0])
            }
            builder.add("quay", at: SIMD2((x + x2) / 2, quayZ)) {
                $0.box(center: SIMD3((x + x2) / 2, 0.4 * s, quayZ - 1.5 * s), size: SIMD3(x2 - x, 0.8 * s, 3 * s))
            }
        }
        builder.material("boat") { Self.plain(0.95, 0.95, 0.95, roughness: 0.5) }
        builder.material("boat.deck") { Self.plain(0.55, 0.38, 0.25) }
        // Катера — у причала вдоль прямой и подальше на рейде.
        for k in 0..<10 {
            let p = SIMD2(x0 + 500 + Float(k) * 170, quayZ + (k % 2 == 0 ? 9 : 30) * s + Float(k % 3) * 8 * s)
            let length = (14 + Float(k % 2) * 10) * s
            builder.add("boat", at: p) {
                $0.box(center: ground(p, 1.2 * s), size: SIMD3(length, 2 * s, length * 0.32))
                $0.box(center: ground(p - SIMD2(length * 0.1, 0), 3.2 * s), size: SIMD3(length * 0.35, 2 * s, length * 0.22))
            }
            builder.add("boat.deck", at: p) {
                $0.box(center: ground(p + SIMD2(length * 0.22, 0), 2.25 * s), size: SIMD3(length * 0.4, 0.1 * s, length * 0.26))
            }
        }
    }

    /// Контейнерный терминал между стартовой прямой и набережной и портальные краны у воды.
    private func addPort(_ builder: SceneryBuilder, from trackZ: Float, quayZ: Float, minX: Float, maxX: Float,
                         rng: inout SeededRandom) {
        let s = propScale
        for (k, color) in Self.containerColors.enumerated() {
            builder.material("container.\(k)") { Self.tiled(Self.ribTexture, tint: color) }
        }
        // Блоки по 5 стопок вдоль и 4 поперёк, между блоками — проезды. Высота стопок в блоке похожая.
        let box = SIMD3<Float>(12.2, 2.6, 2.5) * s
        let gap: Float = 0.6 * s
        let block = SIMD2(5 * (box.x + gap), 4 * (box.z + gap))
        let lane = SIMD2<Float>(10, 9) * s
        // Терминал — в полосе у набережной, там, где трасса отходит от воды (у концов стартовой прямой).
        var z = trackZ - 130 * s
        while z + block.y < quayZ - 22 * s {
            var x = minX
            while x + block.x < maxX {
                defer { x += block.x + lane.x }
                let center = SIMD2(x, z) + block / 2
                let base = rng.next(in: 1...3.99)
                let radius = simd_length(block) / 2
                guard clearance(center) - radius > 6 * s, builder.isFree(center, radius: radius) else { continue }
                builder.reserve(center, radius: radius)
                for i in 0..<5 {
                    for j in 0..<4 {
                        let stack = Int(base + rng.next(in: -1...0.99))
                        let color = Int(rng.next(in: 0...0.999) * Float(Self.containerColors.count))
                        guard stack > 0 else { continue }
                        let p = SIMD2(x + (Float(i) + 0.5) * (box.x + gap), z + (Float(j) + 0.5) * (box.z + gap))
                        builder.add("container.\(color)", at: p) {
                            for level in 0..<stack {
                                $0.box(center: ground(p, box.y * (Float(level) + 0.5)), size: box, tile: SIMD2(2 * s, box.y))
                            }
                        }
                    }
                }
            }
            z += block.y + lane.y
        }

        builder.material("crane") { Self.plain(0.95, 0.6, 0.12, roughness: 0.6) }
        let height = 30 * s, gauge = 16 * s, span = 18 * s
        // Краны — на причале у концов прямой, там, где они не загораживают трассу.
        var placed = 0
        for x in stride(from: minX, to: maxX, by: 40 * s) where placed < 4 {
            let p = SIMD2(x, quayZ - gauge / 2 - 2 * s)
            guard clearance(p) > 30 * s, builder.isFree(p, radius: span) else { continue }
            builder.reserve(p, radius: 2 * span)
            placed += 1
            builder.add("crane", at: p) {
                for dx: Float in [-span / 2, span / 2] {
                    for dz: Float in [-gauge / 2, gauge / 2] {
                        $0.box(center: ground(p + SIMD2(dx, dz), height / 2), size: SIMD3(1.2 * s, height, 1.2 * s))
                    }
                    $0.box(center: ground(p + SIMD2(dx, 0), height * 0.55), size: SIMD3(1 * s, 1 * s, gauge))
                }
                // Стрела над водой и противовес над берегом.
                let boomLength = gauge + 40 * s
                $0.box(center: ground(p + SIMD2(0, boomLength / 2 - gauge / 2 - 8 * s), height + 1.5 * s),
                       size: SIMD3(span + 1.2 * s, 2.5 * s, boomLength))
                $0.box(center: ground(p + SIMD2(0, -gauge / 2 - 4 * s), height + 4 * s), size: SIMD3(span * 0.6, 5 * s, 6 * s))
            }
        }
    }
}
