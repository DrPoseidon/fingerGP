import RealityKit
import UIKit
import simd

/// Трасса, построенная по замкнутой осевой линии. Все координаты — (x, z) на земле, метры.
/// Осевая линия хранится равномерными отсчётами примерно через 1 м; индекс 0 — линия старта,
/// индексы растут по направлению гонки.
struct Track {
    let definition: TrackDefinition
    let points: [SIMD2<Float>]
    let tangents: [SIMD2<Float>]
    /// Нормаль влево-вправо от направления движения (для построения ленты трассы).
    let normals: [SIMD2<Float>]
    /// Насколько далеко можно отступить от оси по +нормали / −нормали, не «вывернув» ленту
    /// на внутренней стороне крутого поворота (≈ радиус поворота).
    private let maxOffsetPlus: [Float]
    private let maxOffsetMinus: [Float]
    let step: Float
    let length: Float
    let halfWidth: Float
    let curbWidth: Float = 1.8
    let center: SIMD2<Float>

    init(_ definition: TrackDefinition) {
        self.definition = definition
        halfWidth = definition.width / 2

        var dense: [SIMD2<Float>]
        switch definition.shape {
        case let .stadium(straight, radius):
            dense = Track.stadium(straight: straight, radius: radius)
        case let .spline(control, longSide):
            dense = Track.spline(control, longSide: longSide)
        }
        let (resampled, step) = Track.resample(dense, step: 1)
        points = Track.smooth(resampled, passes: definition.id == .oval ? 0 : 3)
        self.step = step
        length = step * Float(points.count)

        let pts = points
        let n = pts.count
        let tans = (0..<n).map { simd_normalize(pts[($0 + 1) % n] - pts[($0 - 1 + n) % n]) }
        tangents = tans
        let norms = tans.map { SIMD2($0.y, -$0.x) }
        normals = norms
        var plus = [Float](repeating: .infinity, count: n), minus = plus
        for i in 0..<n {
            let k = 3
            let dt = (tans[(i + k) % n] - tans[(i - k + n) % n]) / (2 * Float(k) * step)
            let curvature = simd_length(dt)
            guard curvature > 1e-4 else { continue }
            let limit = 0.8 / curvature
            if simd_dot(dt, norms[i]) > 0 { plus[i] = limit } else { minus[i] = limit }
        }
        maxOffsetPlus = plus
        maxOffsetMinus = minus

        let minP = pts.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let maxP = pts.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        center = (minP + maxP) / 2
    }

    // MARK: - Геометрия

    /// Точка и направление осевой линии на расстоянии s от старта (s может быть любым — берётся по модулю).
    func frame(atDistance s: Float) -> (position: SIMD2<Float>, tangent: SIMD2<Float>) {
        var s = s.truncatingRemainder(dividingBy: length)
        if s < 0 { s += length }
        let f = s / step
        let i = Int(f) % points.count, j = (i + 1) % points.count
        let t = f - Float(Int(f))
        let tangent = simd_normalize(simd_mix(tangents[i], tangents[j], SIMD2(repeating: t)))
        return (simd_mix(points[i], points[j], SIMD2(repeating: t)), tangent)
    }

    func nearestIndex(_ p: SIMD2<Float>) -> Int {
        var best = 0
        var bestD = Float.infinity
        for (i, q) in points.enumerated() {
            let d = simd_distance_squared(p, q)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// Расстояние вдоль трассы от старта до ближайшей к точке позиции.
    func nearestIndexDistance(_ p: SIMD2<Float>) -> Float { Float(nearestIndex(p)) * step }

    /// Расстояние от точки до осевой линии.
    func distanceFromCenterline(_ p: SIMD2<Float>) -> Float {
        let n = points.count
        let i = nearestIndex(p)
        return min(segmentDistance(p, points[(i - 1 + n) % n], points[i]),
                   segmentDistance(p, points[i], points[(i + 1) % n]))
    }

    /// Быстрая грубая оценка (по каждой 4-й точке, погрешность ~2 м) — для расстановки декораций.
    private func approximateDistance(_ p: SIMD2<Float>) -> Float {
        var best = Float.infinity
        for i in stride(from: 0, to: points.count, by: 4) { best = min(best, simd_distance_squared(p, points[i])) }
        return sqrt(best) - 2
    }

    private func segmentDistance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let t = simd_clamp(simd_dot(p - a, ab) / max(simd_length_squared(ab), 1e-6), 0, 1)
        return simd_distance(p, a + ab * t)
    }

    /// Стартовая позиция машины: чуть позади линии старта, по направлению гонки.
    var startPose: (position: SIMD2<Float>, heading: Float) {
        let f = frame(atDistance: -14)
        return (f.position, atan2(f.tangent.x, f.tangent.y))
    }

    /// Точки по обеим кромкам с запасом — по ним камера подбирает ракурс, чтобы вся трасса была в кадре.
    func boundaryPoints() -> [SIMD3<Float>] {
        let off = halfWidth + curbWidth + 3
        return stride(from: 0, to: points.count, by: 3).flatMap { i in
            [points[i] + normals[i] * off, points[i] - normals[i] * off].map { SIMD3($0.x, 0, $0.y) }
        }
    }

    // MARK: - Построение осевой линии

    private static func stadium(straight l: Float, radius r: Float) -> [SIMD2<Float>] {
        let arc = Float.pi * r
        let perimeter = 2 * l + 2 * arc
        return stride(from: Float(0), to: perimeter, by: 0.25).map { s0 in
            var s = s0
            if s < l { return SIMD2(-l / 2 + s, r) }
            s -= l
            if s < arc { let t = s / r; return SIMD2(l / 2 + r * sin(t), r * cos(t)) }
            s -= arc
            if s < l { return SIMD2(l / 2 - s, -r) }
            s -= l
            let t = s / r
            return SIMD2(-l / 2 - r * sin(t), -r * cos(t))
        }
    }

    /// Центрипетальный сплайн Катмулла–Рома через опорные точки схемы, отмасштабированный в метры.
    private static func spline(_ control: [SIMD2<Float>], longSide: Float) -> [SIMD2<Float>] {
        let minP = control.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let maxP = control.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        let size = maxP - minP
        let scale = longSide / max(size.x, size.y)
        let mid = (minP + maxP) / 2
        // Ось y картинки направлена вниз — как и ось z мира при взгляде сверху, так что отражать не нужно.
        let p = control.map { ($0 - mid) * scale }

        let n = p.count
        var out: [SIMD2<Float>] = []
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            let segments = max(4, Int(simd_distance(p1, p2) / 0.5))
            for k in 0..<segments {
                out.append(catmullRom(p0, p1, p2, p3, Float(k) / Float(segments)))
            }
        }
        return out
    }

    private static func catmullRom(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>,
                                   _ u: Float) -> SIMD2<Float> {
        func knot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { max(sqrt(simd_distance(a, b)), 1e-3) }
        let t0: Float = 0
        let t1 = t0 + knot(p0, p1)
        let t2 = t1 + knot(p1, p2)
        let t3 = t2 + knot(p2, p3)
        let t = t1 + (t2 - t1) * u
        let a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
        let a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
        let a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
        let b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
        let b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
        return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
    }

    /// Равномерная передискретизация замкнутой ломаной с шагом ≈ step.
    private static func resample(_ line: [SIMD2<Float>], step: Float) -> ([SIMD2<Float>], Float) {
        var cumulative: [Float] = [0]
        for i in 0..<line.count {
            cumulative.append(cumulative[i] + simd_distance(line[i], line[(i + 1) % line.count]))
        }
        let total = cumulative.last!
        let n = max(Int(total / step), 8)
        let realStep = total / Float(n)
        var out: [SIMD2<Float>] = []
        var seg = 0
        for k in 0..<n {
            let s = Float(k) * realStep
            while cumulative[seg + 1] < s { seg += 1 }
            let a = line[seg], b = line[(seg + 1) % line.count]
            let t = (s - cumulative[seg]) / max(cumulative[seg + 1] - cumulative[seg], 1e-6)
            out.append(simd_mix(a, b, SIMD2(repeating: t)))
        }
        return (out, realStep)
    }

    /// Лёгкое сглаживание, чтобы убрать изломы от ручной оцифровки схемы.
    private static func smooth(_ pts: [SIMD2<Float>], passes: Int) -> [SIMD2<Float>] {
        var p = pts
        let n = p.count
        for _ in 0..<passes {
            p = (0..<n).map { i in
                (p[(i - 2 + n) % n] + p[(i - 1 + n) % n] + p[i] + p[(i + 1) % n] + p[(i + 2) % n]) / 5
            }
        }
        return p
    }

    // MARK: - Сцена

    func makeEntity() -> Entity {
        let root = Entity()

        let grass = ModelEntity(
            mesh: .generatePlane(width: 4000, depth: 4000),
            materials: [SimpleMaterial(color: UIColor(red: 0.36, green: 0.62, blue: 0.30, alpha: 1), roughness: 1, isMetallic: false)])
        root.addChild(grass)

        let asphalt = SimpleMaterial(color: UIColor(white: 0.28, alpha: 1), roughness: 0.9, isMetallic: false)
        let red = SimpleMaterial(color: UIColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 1), roughness: 0.8, isMetallic: false)
        let white = SimpleMaterial(color: .white, roughness: 0.8, isMetallic: false)
        let black = SimpleMaterial(color: UIColor(white: 0.08, alpha: 1), roughness: 0.8, isMetallic: false)

        add(ribbon(from: -halfWidth, to: halfWidth, y: 0.02), asphalt, to: root)
        // Поребрики — чередование красного и белого каждые 2 м, с обеих сторон.
        for (a, b) in [(-halfWidth - curbWidth, -halfWidth), (halfWidth, halfWidth + curbWidth)] {
            add(ribbon(from: a, to: b, y: 0.04) { ($0 / 2) % 2 == 0 }, red, to: root)
            add(ribbon(from: a, to: b, y: 0.04) { ($0 / 2) % 2 == 1 }, white, to: root)
        }

        // Шахматный стартовый створ поперёк трассы в точке 0.
        let cell: Float = 1
        let cols = Int(definition.width / cell)
        let p0 = points[0], t = tangents[0], nrm = normals[0]
        var whiteCells: [[SIMD3<Float>]] = [], blackCells: [[SIMD3<Float>]] = []
        for row in 0..<2 {
            for col in 0..<cols {
                let a = Float(row) * cell - cell, b = -halfWidth + Float(col) * cell
                let corners = [(a, b), (a + cell, b), (a + cell, b + cell), (a, b + cell)].map { (u, v) -> SIMD3<Float> in
                    let q = p0 + t * u + nrm * v
                    return SIMD3(q.x, 0.05, q.y)
                }
                if (row + col) % 2 == 0 { whiteCells.append(corners) } else { blackCells.append(corners) }
            }
        }
        add(mesh(fromQuads: whiteCells), white, to: root)
        add(mesh(fromQuads: blackCells), black, to: root)

        addTrees(to: root)
        return root
    }

    private func add(_ mesh: MeshResource?, _ material: RealityKit.Material, to parent: Entity) {
        guard let mesh else { return }
        parent.addChild(ModelEntity(mesh: mesh, materials: [material]))
    }

    /// Лента вдоль осевой линии между смещениями `a` и `b` по нормали.
    private func ribbon(from a: Float, to b: Float, y: Float, include: (Int) -> Bool = { _ in true }) -> MeshResource? {
        let n = points.count
        var quads: [[SIMD3<Float>]] = []
        for i in 0..<n where include(i) {
            let j = (i + 1) % n
            let v = [offset(i, a), offset(j, a), offset(j, b), offset(i, b)]
            quads.append(v.map { SIMD3($0.x, y, $0.y) })
        }
        return mesh(fromQuads: quads)
    }

    /// Точка на смещении v от оси с ограничением на внутренней стороне крутого поворота.
    private func offset(_ i: Int, _ v: Float) -> SIMD2<Float> {
        let clamped = v >= 0 ? min(v, maxOffsetPlus[i]) : max(v, -maxOffsetMinus[i])
        return points[i] + normals[i] * clamped
    }

    private func mesh(fromQuads quads: [[SIMD3<Float>]]) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for q in quads {
            let base = UInt32(positions.count)
            positions.append(contentsOf: q)
            // Лицевая сторона должна смотреть вверх (+Y): при необходимости меняем порядок обхода.
            let up = simd_cross(q[1] - q[0], q[2] - q[0]).y > 0
            let order: [UInt32] = up ? [0, 1, 2, 0, 2, 3] : [0, 2, 1, 0, 3, 2]
            indices.append(contentsOf: order.map { base + $0 })
        }
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count))
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private func addTrees(to root: Entity) {
        let trunkMesh = MeshResource.generateCylinder(height: 1.6, radius: 0.35)
        let crownMesh = MeshResource.generateCone(height: 4.5, radius: 1.8)
        let trunkMat = SimpleMaterial(color: UIColor(red: 0.42, green: 0.27, blue: 0.15, alpha: 1), roughness: 1, isMetallic: false)
        let crownMat = SimpleMaterial(color: UIColor(red: 0.15, green: 0.45, blue: 0.20, alpha: 1), roughness: 1, isMetallic: false)

        let minP = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) } - 40
        let maxP = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) } + 40
        let area = (maxP.x - minP.x) * (maxP.y - minP.y)
        let count = min(Int(area / 1500), 700)
        // Деревья на больших трассах крупнее, чтобы их было видно с дальней камеры.
        let sizeScale = definition.carScale / 1.5

        var rng = SeededRandom(seed: definition.id.rawValue.utf8.reduce(7) { $0 &* 31 &+ UInt64($1) })
        var placed = 0, attempts = 0
        while placed < count && attempts < count * 20 {
            attempts += 1
            let p = SIMD2<Float>(rng.next(in: minP.x...maxP.x), rng.next(in: minP.y...maxP.y))
            // Не ставим деревья на трассу и в зону сразу за ней.
            guard approximateDistance(p) > halfWidth + curbWidth + 5 * sizeScale else { continue }
            let tree = Entity()
            let trunk = ModelEntity(mesh: trunkMesh, materials: [trunkMat])
            trunk.position.y = 0.8
            let crown = ModelEntity(mesh: crownMesh, materials: [crownMat])
            crown.position.y = 1.6 + 2.25
            tree.addChild(trunk)
            tree.addChild(crown)
            tree.position = SIMD3(p.x, 0, p.y)
            tree.scale = SIMD3(repeating: rng.next(in: 0.7...1.2) * sizeScale)
            root.addChild(tree)
            placed += 1
        }
    }
}

/// Детерминированный ГПСЧ, чтобы расстановка декораций не менялась между запусками.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next(in range: ClosedRange<Float>) -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Float(state >> 40) / Float(1 << 24)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
