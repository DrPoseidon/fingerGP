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
    let maxOffsetPlus: [Float]
    let maxOffsetMinus: [Float]
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

    /// Быстрый поиск ближайшей точки рядом с прошлой (машина за кадр сдвигается на метр-другой).
    /// Если на краю окна расстояние всё ещё убывает, ищет по всей трассе.
    func nearestIndex(_ p: SIMD2<Float>, near hint: Int, window: Int = 60) -> Int {
        let n = points.count
        var best = hint, bestD = Float.infinity
        for k in -window...window {
            let i = ((hint + k) % n + n) % n
            let d = simd_distance_squared(p, points[i])
            if d < bestD { bestD = d; best = i }
        }
        let offset = ((best - hint) % n + n) % n
        let distanceFromHint = min(offset, n - offset)
        return distanceFromHint >= window - 1 ? nearestIndex(p) : best
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
    func approximateDistance(_ p: SIMD2<Float>) -> Float {
        var best = Float.infinity
        for i in stride(from: 0, to: points.count, by: 4) { best = min(best, simd_distance_squared(p, points[i])) }
        return sqrt(best) - 2
    }

    func segmentDistance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
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
}
