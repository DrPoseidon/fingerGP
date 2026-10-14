import RealityKit
import UIKit

/// Лёгкий призрак лучшего круга: «голограмма» болида из нескольких простых фигур
/// с полупрозрачным неосвещаемым материалом и без тени.
///
/// Полупрозрачная копия настоящей модели (≈90 тыс. треугольников, 124 детали) сильно роняла FPS:
/// каждая деталь рисуется в прозрачном проходе с сортировкой и освещением. Здесь — 9 простых мешей.
@MainActor
final class GhostCar {
    let root = Entity()

    init(scale: Float) {
        var material = UnlitMaterial(color: UIColor(red: 0.72, green: 0.9, blue: 1, alpha: 1))
        material.blending = .transparent(opacity: 0.45)

        // Координаты модели: метры, нос в +Z, y вверх (см. CAR_MODEL_GUIDE.md).
        func part(_ mesh: MeshResource, at position: SIMD3<Float>, rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = position
            entity.orientation = rotation
            root.addChild(entity)
        }
        part(.generateBox(width: 0.55, height: 0.35, depth: 2.9, cornerRadius: 0.12), at: [0, 0.35, 0.35])   // корпус и нос
        part(.generateBox(width: 1.35, height: 0.42, depth: 1.25, cornerRadius: 0.15), at: [0, 0.35, -0.45]) // понтоны
        part(.generateBox(width: 2.0, height: 0.08, depth: 0.4), at: [0, 0.14, 1.72])                       // переднее крыло
        part(.generateBox(width: 1.35, height: 0.1, depth: 0.4), at: [0, 0.92, -1.7])                       // заднее крыло
        part(.generateSphere(radius: 0.2), at: [0, 0.68, -0.05])                                            // шлем
        let wheel = MeshResource.generateCylinder(height: 0.38, radius: 0.43)
        let axle = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        for (x, z) in [(Float(0.88), Float(1.095)), (-0.88, 1.095), (0.88, -1.243), (-0.88, -1.243)] {
            part(wheel, at: [x, 0.43, z], rotation: axle)
        }

        root.scale = SIMD3(repeating: scale)
        root.components.set(DynamicLightShadowComponent(castsShadow: false))
    }

    func update(position: SIMD2<Float>, heading: Float) {
        root.position = SIMD3(position.x, 0, position.y)
        root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
    }
}
