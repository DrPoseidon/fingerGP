import RealityKit
import UIKit
import simd

/// Окружение трассы: от него зависят растительность и (дальше) постройки.
enum SceneryTheme {
    case stadium, city, mountains, forest

    /// Сколько квадратных метров на одно дерево, предел числа деревьев и доля елей.
    var trees: (areaPerTree: Float, limit: Int, conifers: Float) {
        switch self {
        case .stadium: (2600, 350, 0.3)
        case .city: (3000, 300, 0)
        case .mountains: (1500, 700, 0.9)
        case .forest: (1000, 1000, 0.55)
        }
    }
}

extension Track {
    /// Деревья: ели (два конуса) и лиственные (ствол и «облако»), в двух-трёх оттенках зелени.
    @MainActor
    func addTrees(_ builder: SceneryBuilder) {
        let mat = { (r: CGFloat, g: CGFloat, b: CGFloat) -> RealityKit.Material in
            SimpleMaterial(color: UIColor(red: r, green: g, blue: b, alpha: 1), roughness: 1, isMetallic: false)
        }
        builder.material("tree.trunk") { mat(0.42, 0.27, 0.15) }
        builder.material("tree.conifer") { mat(0.13, 0.40, 0.20) }
        builder.material("tree.conifer.dark") { mat(0.10, 0.32, 0.17) }
        builder.material("tree.leafy") { mat(0.30, 0.58, 0.22) }
        builder.material("tree.leafy.light") { mat(0.48, 0.66, 0.25) }

        let minP = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) } - 40
        let maxP = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) } + 40
        let area = (maxP.x - minP.x) * (maxP.y - minP.y)
        let settings = definition.scenery.trees
        let count = min(Int(area / settings.areaPerTree), settings.limit)
        // Деревья на больших трассах крупнее, чтобы их было видно с дальней камеры.
        let sizeScale = definition.carScale / 1.5

        var rng = SeededRandom(seed: definition.id.rawValue.utf8.reduce(7) { $0 &* 31 &+ UInt64($1) })
        var placed = 0, attempts = 0
        while placed < count && attempts < count * 20 {
            attempts += 1
            let p = SIMD2<Float>(rng.next(in: minP.x...maxP.x), rng.next(in: minP.y...maxP.y))
            let scale = rng.next(in: 0.7...1.2) * sizeScale
            let conifer = rng.next(in: 0...1) < settings.conifers
            let shade = rng.next(in: 0...1) < 0.4
            let phase = rng.next(in: 0...(2 * .pi))
            // Не ставим деревья на трассу, в зону сразу за ней и поверх щитов.
            guard approximateDistance(p) > halfWidth + curbWidth + 5 * sizeScale,
                  builder.isFree(p, radius: 2 * scale) else { continue }
            let base = SIMD3(p.x, 0, p.y)
            if conifer {
                builder.add("tree.trunk", at: p) { $0.prism(base: base, radius: 0.3 * scale, height: 1.4 * scale, sides: 5, phase: phase) }
                builder.add(shade ? "tree.conifer.dark" : "tree.conifer", at: p) {
                    $0.cone(base: base + SIMD3(0, 1.0 * scale, 0), radius: 2.0 * scale, height: 3.3 * scale, sides: 7, phase: phase)
                    $0.cone(base: base + SIMD3(0, 2.9 * scale, 0), radius: 1.45 * scale, height: 2.8 * scale, sides: 7, phase: phase + 0.4)
                }
            } else {
                builder.add("tree.trunk", at: p) { $0.prism(base: base, radius: 0.32 * scale, height: 2.2 * scale, sides: 5, phase: phase) }
                builder.add(shade ? "tree.leafy.light" : "tree.leafy", at: p) {
                    $0.blob(center: base + SIMD3(0, 3.5 * scale, 0), radius: SIMD3(2.0, 1.7, 2.0) * scale, yaw: phase)
                }
            }
            placed += 1
        }
    }
}
