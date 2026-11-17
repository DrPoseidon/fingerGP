import RealityKit
import simd

/// Накопитель треугольников для неподвижных декораций. Все грани — плоские (у каждой своя нормаль),
/// это даёт «низкополигональный» вид и не требует сглаживания.
struct MeshBatch {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    /// Четырёхугольник a-b-c-d (a — левый нижний, против часовой стрелки, если смотреть на лицевую сторону).
    /// `facing` — куда должна смотреть лицевая сторона; если обход оказался обратным, он разворачивается.
    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       facing: SIMD3<Float>? = nil) {
        var n = simd_cross(b - a, c - a)
        guard simd_length_squared(n) > 1e-12 else { return }
        n = simd_normalize(n)
        let base = UInt32(positions.count)
        positions += [a, b, c, d]
        uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        if let facing, simd_dot(n, facing) < 0 {
            normals += Array(repeating: -n, count: 4)
            indices += [0, 2, 1, 0, 3, 2].map { base + $0 }
        } else {
            normals += Array(repeating: n, count: 4)
            indices += [0, 1, 2, 0, 2, 3].map { base + $0 }
        }
    }

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, facing: SIMD3<Float>) {
        var n = simd_cross(b - a, c - a)
        guard simd_length_squared(n) > 1e-12 else { return }
        n = simd_normalize(n)
        let flip = simd_dot(n, facing) < 0
        let base = UInt32(positions.count)
        positions += flip ? [a, c, b] : [a, b, c]
        normals += Array(repeating: flip ? -n : n, count: 3)
        uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)]
        indices += [base, base + 1, base + 2]
    }

    /// Прямоугольная панель с центром `center`, лицом к `normal`; `up` — верх картинки.
    mutating func panel(center: SIMD3<Float>, normal: SIMD3<Float>, up: SIMD3<Float>, width: Float, height: Float) {
        let right = simd_normalize(simd_cross(up, normal)) * (width / 2)
        let u = up * (height / 2)
        quad(center - right - u, center + right - u, center + right + u, center - right + u, facing: normal)
    }

    /// Параллелепипед: центр, полуразмеры по осям `right`, `up`, `forward` (взаимно перпендикулярные единичные).
    /// Нижняя грань не строится — её никогда не видно.
    mutating func box(center c: SIMD3<Float>, size: SIMD3<Float>,
                      right r: SIMD3<Float> = [1, 0, 0], up u: SIMD3<Float> = [0, 1, 0], forward f: SIMD3<Float> = [0, 0, 1]) {
        let h = size / 2
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (f * h.z, r * h.x, u * h.y), (-f * h.z, r * h.x, u * h.y),
            (r * h.x, f * h.z, u * h.y), (-r * h.x, f * h.z, u * h.y),
            (u * h.y, r * h.x, f * h.z),
        ]
        for (n, s, t) in faces {
            let o = c + n
            quad(o - s - t, o + s - t, o + s + t, o - s + t, facing: n)
        }
    }

    /// Вертикальная призма без крышек (стволы, столбы).
    mutating func prism(base: SIMD3<Float>, radius: Float, height: Float, sides: Int, phase: Float = 0) {
        let ring = (0...sides).map { k -> SIMD3<Float> in
            let a = phase + Float(k) / Float(sides) * 2 * .pi
            return SIMD3(cos(a), 0, sin(a)) * radius
        }
        for k in 0..<sides {
            let a = base + ring[k], b = base + ring[k + 1]
            let up = SIMD3<Float>(0, height, 0)
            quad(a, b, b + up, a + up, facing: (ring[k] + ring[k + 1]) / 2)
        }
    }

    /// Конус без донышка (кроны елей).
    mutating func cone(base: SIMD3<Float>, radius: Float, height: Float, sides: Int, phase: Float = 0) {
        let apex = base + SIMD3(0, height, 0)
        for k in 0..<sides {
            let a0 = phase + Float(k) / Float(sides) * 2 * .pi
            let a1 = phase + Float(k + 1) / Float(sides) * 2 * .pi
            let p = base + SIMD3(cos(a0), 0, sin(a0)) * radius
            let q = base + SIMD3(cos(a1), 0, sin(a1)) * radius
            triangle(p, q, apex, facing: (p + q) / 2 - base + SIMD3(0, radius * 0.5, 0))
        }
    }

    /// Икосаэдр, растянутый по осям, — «облако» лиственной кроны.
    mutating func blob(center: SIMD3<Float>, radius: SIMD3<Float>, yaw: Float = 0) {
        let (c, s) = (cos(yaw), sin(yaw))
        let v = MeshBatch.icosahedron.map { p -> SIMD3<Float> in
            center + SIMD3(p.x * c - p.z * s, p.y, p.x * s + p.z * c) * radius
        }
        for f in MeshBatch.icosahedronFaces {
            let a = v[f.0], b = v[f.1], d = v[f.2]
            triangle(a, b, d, facing: (a + b + d) / 3 - center)
        }
    }

    func resource() -> MeshResource? {
        guard !isEmpty else { return nil }
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static let icosahedron: [SIMD3<Float>] = {
        let t: Float = (1 + Float(5).squareRoot()) / 2
        let raw: [SIMD3<Float>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ]
        return raw.map(simd_normalize)
    }()

    private static let icosahedronFaces: [(Int, Int, Int)] = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]
}
