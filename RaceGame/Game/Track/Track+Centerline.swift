import RealityKit
import UIKit
import simd

/// Построение осевой линии: овал-«стадион» или сплайн по точкам схемы, равномерные отсчёты, сглаживание.
extension Track {
    static func stadium(straight l: Float, radius r: Float) -> [SIMD2<Float>] {
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
    static func spline(_ control: [SIMD2<Float>], longSide: Float) -> [SIMD2<Float>] {
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

    static func catmullRom(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>,
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
    static func resample(_ line: [SIMD2<Float>], step: Float) -> ([SIMD2<Float>], Float) {
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
    static func smooth(_ pts: [SIMD2<Float>], passes: Int) -> [SIMD2<Float>] {
        var p = pts
        let n = p.count
        for _ in 0..<passes {
            p = (0..<n).map { i in
                (p[(i - 2 + n) % n] + p[(i - 1 + n) % n] + p[i] + p[(i + 1) % n] + p[(i + 2) % n]) / 5
            }
        }
        return p
    }
}
