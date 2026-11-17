import RealityKit
import UIKit
import simd

/// 3D-сцена трассы: асфальт, поребрики, линии старта и секторов, трава; декорации — в Scenery/.
extension Track {
    @MainActor
    func makeEntity() -> Entity {
        let root = Entity()

        let grass = ModelEntity(
            mesh: .generatePlane(width: 4000, depth: 4000),
            materials: [SimpleMaterial(color: definition.scenery.groundColor, roughness: 1, isMetallic: false)])
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

        // Отсечки секторов (те же, что в LapTimer и на мини-карте) — жёлтые полосы поперёк асфальта.
        let yellow = SimpleMaterial(color: UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1), roughness: 0.8, isMetallic: false)
        var sectorLines: [[SIMD3<Float>]] = []
        for k in 1..<LapTimer.sectorCount {
            let i = points.count * k / LapTimer.sectorCount
            let p = points[i], t = tangents[i], nrm = normals[i]
            let offsets: [(Float, Float)] = [(-0.6, -halfWidth), (0.6, -halfWidth), (0.6, halfWidth), (-0.6, halfWidth)]
            var corners: [SIMD3<Float>] = []
            for (u, v) in offsets {
                let q: SIMD2<Float> = p + t * u + nrm * v
                corners.append(SIMD3(q.x, 0.05, q.y))
            }
            sectorLines.append(corners)
        }
        add(mesh(fromQuads: sectorLines), yellow, to: root)

        let scenery = SceneryBuilder()
        addTrackside(scenery)
        if definition.scenery == .city { addCity(scenery) }
        addTrees(scenery)
        scenery.build(into: root)
        return root
    }

    func add(_ mesh: MeshResource?, _ material: RealityKit.Material, to parent: Entity) {
        guard let mesh else { return }
        parent.addChild(ModelEntity(mesh: mesh, materials: [material]))
    }

    /// Лента вдоль осевой линии между смещениями `a` и `b` по нормали.
    func ribbon(from a: Float, to b: Float, y: Float, include: (Int) -> Bool = { _ in true }) -> MeshResource? {
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
    func offset(_ i: Int, _ v: Float) -> SIMD2<Float> {
        let clamped = v >= 0 ? min(v, maxOffsetPlus[i]) : max(v, -maxOffsetMinus[i])
        return points[i] + normals[i] * clamped
    }

    func mesh(fromQuads quads: [[SIMD3<Float>]]) -> MeshResource? {
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
}
