import RealityKit
import UIKit
import simd

/// Горы («Перевал»): скалистые холмы у трассы, вдали — высокие вершины со снегом, валуны
/// и отбойники на внешней стороне поворотов.
@MainActor
extension Track {
    func addMountains(_ builder: SceneryBuilder) {
        let mat = { (r: CGFloat, g: CGFloat, b: CGFloat) -> RealityKit.Material in
            SimpleMaterial(color: UIColor(red: r, green: g, blue: b, alpha: 1), roughness: 1, isMetallic: false)
        }
        builder.material("rock") { mat(0.52, 0.5, 0.48) }
        builder.material("rock.dark") { mat(0.42, 0.4, 0.39) }
        builder.material("hill") { mat(0.33, 0.47, 0.27) }
        builder.material("snow") { mat(0.95, 0.96, 0.98) }

        var rng = SeededRandom(seed: 0x9A55)
        addGuardrails(builder)
        addLake(builder, rng: &rng)
        addPeaks(builder, rng: &rng)
        addBoulders(builder, count: 160, rng: &rng)
    }

    private var propScale: Float { definition.carScale / 1.5 }

    private func ground(_ p: SIMD2<Float>, _ y: Float = 0) -> SIMD3<Float> { SIMD3(p.x, y, p.y) }

    private func clearance(_ p: SIMD2<Float>) -> Float { approximateDistance(p) - halfWidth - curbWidth }

    // MARK: - Вершины и холмы

    /// Чем дальше от трассы, тем выше гора: у трассы — невысокие скалистые холмы, вдали — вершины
    /// со снегом. Высота не больше расстояния до трассы, чтобы с высокой камеры гора её не закрывала.
    private func addPeaks(_ builder: SceneryBuilder, rng: inout SeededRandom) {
        let s = propScale
        let minP = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) } - 1100
        let maxP = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) } + 1100
        for _ in 0..<1400 {
            let c = SIMD2(rng.next(in: minP.x...maxP.x), rng.next(in: minP.y...maxP.y))
            let room = clearance(c)
            let radius = min(rng.next(in: 14...150) * s, room * 0.6)
            guard radius > 12 * s, builder.isFree(c, radius: radius * 0.7) else { continue }
            let height = min(radius * rng.next(in: 0.6...1.5), room * 0.85)
            builder.reserve(c, radius: radius * 0.9)
            addPeak(builder, center: c, radius: radius, height: height, snowy: height > 70 * s, rocky: height > 40 * s,
                    rng: &rng)
        }
        // Небольшие скалы у самой трассы.
        var crags = 0
        for _ in 0..<3000 where crags < 70 {
            let c = SIMD2(rng.next(in: (minP.x + 1000)...(maxP.x - 1000)), rng.next(in: (minP.y + 1000)...(maxP.y - 1000)))
            let room = clearance(c)
            let radius = rng.next(in: 5...11) * s
            guard room > radius + 5 * s, room < 70 * s, builder.isFree(c, radius: radius) else { continue }
            let height = min(radius * rng.next(in: 0.9...1.7), room * 0.85)
            builder.reserve(c, radius: radius)
            addPeak(builder, center: c, radius: radius, height: height, snowy: false, rocky: true, rng: &rng)
            crags += 1
        }
    }

    /// Гора из неровных колец: основание, середина и вершина. Низ у холмов зелёный, у высоких гор — скала;
    /// у высоких верх под снегом с неровной границей.
    private func addPeak(_ builder: SceneryBuilder, center c: SIMD2<Float>, radius: Float, height: Float, snowy: Bool,
                         rocky: Bool, rng: inout SeededRandom) {
        let sides = 9
        let phase = rng.next(in: 0...(2 * .pi))
        func ring(_ r: Float, _ y: Float, _ jitter: Float, _ shift: SIMD2<Float>) -> [SIMD3<Float>] {
            (0..<sides).map { k in
                let a = phase + (Float(k) + rng.next(in: -0.25...0.25)) / Float(sides) * 2 * .pi
                let p = c + shift + SIMD2(cos(a), sin(a)) * r * rng.next(in: (1 - jitter)...(1 + jitter))
                return ground(p, y)
            }
        }
        let lean = SIMD2(rng.next(in: -1...1), rng.next(in: -1...1)) * radius * 0.15
        let base = ring(radius, 0, 0.2, .zero)
        let middle = ring(radius * 0.55, height * 0.45, 0.25, lean * 0.5)
        let apex = ground(c + lean, height)
        // Граница снега — на 65–80 % высоты, у каждого ребра своя.
        let snowLine = middle.map { m in m + (apex - m) * rng.next(in: 0.4...0.6) }
        let axis = ground(c, 0)

        func band(_ lower: [SIMD3<Float>], _ upper: [SIMD3<Float>], _ batch: inout MeshBatch) {
            for k in 0..<sides {
                let a = lower[k], b = lower[(k + 1) % sides], d = upper[k], e = upper[(k + 1) % sides]
                let out = (a + b) / 2 - axis
                batch.triangle(a, b, e, facing: out)
                batch.triangle(a, e, d, facing: out)
            }
        }
        func cap(_ ring: [SIMD3<Float>], _ batch: inout MeshBatch) {
            for k in 0..<sides {
                let a = ring[k], b = ring[(k + 1) % sides]
                batch.triangle(a, b, apex, facing: (a + b) / 2 - axis + SIMD3(0, height, 0))
            }
        }
        builder.add(rocky ? "rock.dark" : "hill", at: c) { band(base, middle, &$0) }
        if snowy {
            builder.add("rock", at: c) { band(middle, snowLine, &$0) }
            builder.add("snow", at: c) { cap(snowLine, &$0) }
        } else {
            builder.add("rock", at: c) { cap(middle, &$0) }
        }
    }

    /// Подлесок «Лесного кольца»: озеро на самой большой поляне, кусты, поваленные стволы и валуны.
    func addForestFloor(_ builder: SceneryBuilder) {
        let s = propScale
        var rng = SeededRandom(seed: 0xF0E5)
        addLake(builder, rng: &rng)
        addBoulders(builder, count: 70, rng: &rng)
        builder.material("bush") {
            SimpleMaterial(color: UIColor(red: 0.2, green: 0.45, blue: 0.2, alpha: 1), roughness: 1, isMetallic: false)
        }
        builder.material("log") {
            SimpleMaterial(color: UIColor(red: 0.45, green: 0.32, blue: 0.2, alpha: 1), roughness: 1, isMetallic: false)
        }
        let minP = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) } - 40
        let maxP = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) } + 40
        for _ in 0..<2500 {
            let c = SIMD2(rng.next(in: minP.x...maxP.x), rng.next(in: minP.y...maxP.y))
            guard clearance(c) > 3 * s, builder.isFree(c, radius: 2.5 * s) else { continue }
            let yaw = rng.next(in: 0...6)
            if rng.next(in: 0...1) < 0.12 {
                // Поваленный ствол.
                let length = rng.next(in: 5...9) * s, dir = SIMD2(cos(yaw), sin(yaw))
                builder.reserve(c, radius: length / 2)
                builder.add("log", at: c) {
                    $0.box(center: ground(c, 0.35 * s), size: SIMD3(0.7 * s, 0.7 * s, length),
                           right: SIMD3(-dir.y, 0, dir.x), forward: SIMD3(dir.x, 0, dir.y))
                }
            } else {
                let size = rng.next(in: 1...1.8) * s
                builder.reserve(c, radius: size)
                builder.add("bush", at: c) {
                    $0.blob(center: ground(c, size * 0.35), radius: SIMD3(1.3, 0.8, 1.1) * size, yaw: yaw)
                }
            }
        }
    }

    /// Озеро неровной формы там, где дальше всего до трассы внутри неё, с каменистым берегом.
    private func addLake(_ builder: SceneryBuilder, rng: inout SeededRandom) {
        let s = propScale
        let minP = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let maxP = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        var best = SIMD2<Float>.zero, bestRoom: Float = 0
        for _ in 0..<600 {
            let p = SIMD2(rng.next(in: minP.x...maxP.x), rng.next(in: minP.y...maxP.y))
            let room = clearance(p)
            if room > bestRoom { (best, bestRoom) = (p, room) }
        }
        let radius = min(bestRoom * 0.7, 140 * s)
        guard radius > 20 * s else { return }
        builder.material("lake") {
            SimpleMaterial(color: UIColor(red: 0.2, green: 0.45, blue: 0.62, alpha: 1), roughness: 0.15, isMetallic: false)
        }
        builder.material("shore") {
            SimpleMaterial(color: UIColor(red: 0.6, green: 0.57, blue: 0.5, alpha: 1), roughness: 1, isMetallic: false)
        }
        builder.reserve(best, radius: radius * 1.05)
        let sides = 14
        let edge = (0..<sides).map { k -> SIMD2<Float> in
            let a = Float(k) / Float(sides) * 2 * .pi
            return SIMD2(cos(a) * 1.15, sin(a) * 0.85) * radius * rng.next(in: 0.8...1.05)
        }
        let center = ground(best, 0.04), up = SIMD3<Float>(0, 1, 0)
        builder.add("shore", at: best) {
            for k in 0..<sides {
                let a = edge[k] * 1.08 + best, b = edge[(k + 1) % sides] * 1.08 + best
                $0.triangle(ground(best, 0.03), ground(a, 0.03), ground(b, 0.03), facing: up)
            }
        }
        builder.add("lake", at: best) {
            for k in 0..<sides {
                $0.triangle(center, ground(best + edge[k], 0.04), ground(best + edge[(k + 1) % sides], 0.04), facing: up)
            }
        }
    }

    // MARK: - Валуны

    /// Группы валунов недалеко от трассы — по 1–3 камня, наполовину в земле.
    func addBoulders(_ builder: SceneryBuilder, count: Int, rng: inout SeededRandom) {
        let s = propScale
        let mat = { (r: CGFloat, g: CGFloat, b: CGFloat) -> RealityKit.Material in
            SimpleMaterial(color: UIColor(red: r, green: g, blue: b, alpha: 1), roughness: 1, isMetallic: false)
        }
        builder.material("rock") { mat(0.52, 0.5, 0.48) }
        builder.material("rock.dark") { mat(0.42, 0.4, 0.39) }
        let minP = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) } - 80
        let maxP = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) } + 80
        var placed = 0
        for _ in 0..<(count * 30) where placed < count {
            let c = SIMD2(rng.next(in: minP.x...maxP.x), rng.next(in: minP.y...maxP.y))
            let room = clearance(c)
            guard room > 4 * s, room < 45 * s, builder.isFree(c, radius: 4 * s) else { continue }
            builder.reserve(c, radius: 4 * s)
            placed += 1
            let stones = Int(rng.next(in: 1...3.99))
            for k in 0..<stones {
                let size = rng.next(in: 0.9...2.6) * s * (k == 0 ? 1.3 : 1)
                let p = c + SIMD2(rng.next(in: -2.5...2.5), rng.next(in: -2.5...2.5)) * s * Float(min(k, 1))
                let dark = rng.next(in: 0...1) < 0.4
                let yaw = rng.next(in: 0...6)
                builder.add(dark ? "rock.dark" : "rock", at: c) {
                    $0.blob(center: ground(p, size * 0.25), radius: SIMD3(1.2, 0.75, 1) * size, yaw: yaw)
                }
            }
        }
    }

    // MARK: - Отбойники

    /// Отбойник (стальная лента на столбиках) вдоль внешней стороны поворотов.
    private func addGuardrails(_ builder: SceneryBuilder) {
        let s = propScale
        builder.material("rail") {
            SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), roughness: 0.4, isMetallic: false)
        }
        let n = points.count, k = 6
        let curvature: [Float] = (0..<n).map { i in
            let a = tangents[(i - k + n) % n], b = tangents[(i + k) % n]
            return -atan2(a.x * b.y - a.y * b.x, simd_dot(a, b)) / (2 * Float(k) * step)
        }
        let offset = halfWidth + curbWidth + 1.2 * s
        let every = max(1, Int(3 * s / step))
        for i in stride(from: 0, to: n, by: every) {
            let j = (i + every) % n
            // Только в поворотах (радиус меньше 220 м); у одной ленты — один знак поворота.
            guard abs(curvature[i]) > 1 / 220, abs(curvature[j]) > 1 / 220,
                  (curvature[i] > 0) == (curvature[j] > 0) else { continue }
            let side: Float = curvature[i] > 0 ? -1 : 1
            let a = points[i] + normals[i] * side * offset, b = points[j] + normals[j] * side * offset
            // Рядом другой участок трассы (связка, шпилька) — ленту не ставим.
            guard approximateDistance(a) > offset - 3, approximateDistance(b) > offset - 3 else { continue }
            let along = b - a, len = simd_length(along)
            guard len > 0.1 else { continue }
            let t = along / len
            let forward = SIMD3(t.x, 0, t.y), right = SIMD3(-t.y, 0, t.x)
            let mid = (a + b) / 2
            builder.reserve(mid, radius: 2 * s)
            builder.add("rail", at: mid) {
                $0.box(center: ground(mid, 0.8 * s), size: SIMD3(0.5 * s, 0.6 * s, len + 0.05),
                       right: right, forward: forward)
                $0.box(center: ground(a, 0.5 * s), size: SIMD3(0.25 * s, 1 * s, 0.25 * s), right: right, forward: forward)
            }
        }
    }
}
