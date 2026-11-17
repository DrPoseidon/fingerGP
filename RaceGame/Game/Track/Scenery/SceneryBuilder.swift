import RealityKit
import simd

/// Сборщик неподвижных декораций. Всё, что нарисовано одним материалом в одном квадрате карты,
/// склеивается в один меш: сотни деревьев и щитов — это десятки объектов сцены, а не тысячи.
/// Разбивка на квадраты оставляет отсечение того, что не попало в кадр.
@MainActor
final class SceneryBuilder {
    private static let cellSize: Float = 300

    private struct Key: Hashable {
        let material: String
        let cell: SIMD2<Int32>
    }

    private var materials: [String: RealityKit.Material] = [:]
    private var batches: [Key: MeshBatch] = [:]
    /// Занятые места (центр, радиус): деревья не ставятся поверх щитов и табличек.
    private var reserved: [(center: SIMD2<Float>, radius: Float)] = []

    func material(_ name: String, _ make: () -> RealityKit.Material) {
        if materials[name] == nil { materials[name] = make() }
    }

    /// Добавить геометрию материала `name` в квадрат карты, где находится `point`.
    func add(_ name: String, at point: SIMD2<Float>, _ body: (inout MeshBatch) -> Void) {
        let cell = SIMD2<Int32>(Int32((point.x / Self.cellSize).rounded(.down)),
                                Int32((point.y / Self.cellSize).rounded(.down)))
        body(&batches[Key(material: name, cell: cell), default: MeshBatch()])
    }

    func reserve(_ center: SIMD2<Float>, radius: Float) { reserved.append((center, radius)) }

    func isFree(_ point: SIMD2<Float>, radius: Float) -> Bool {
        reserved.allSatisfy { simd_distance($0.center, point) > $0.radius + radius }
    }

    func build(into root: Entity) {
        for (key, batch) in batches {
            guard let material = materials[key.material], let mesh = batch.resource() else { continue }
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
    }
}
