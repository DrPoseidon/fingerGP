import SwiftUI
import RealityKit
import Combine

/// Подиум гаража: машина в выбранной ливрее медленно вращается.
struct GaragePreview: UIViewRepresentable {
    let car: CarModel
    let livery: Livery

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.13, green: 0.15, blue: 0.2, alpha: 1))
        context.coordinator.setUp(view)
        context.coordinator.show(car: car, livery: livery)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.show(car: car, livery: livery)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator {
        private let turntable = Entity()
        private var shown: (car: String, livery: String)?
        private var subscription: Cancellable?
        private var loadTask: Task<Void, Never>?

        func setUp(_ view: ARView) {
            let anchor = AnchorEntity(world: .zero)
            view.scene.addAnchor(anchor)
            anchor.addChild(turntable)

            var floor = PhysicallyBasedMaterial()
            floor.baseColor = .init(tint: UIColor(red: 0.2, green: 0.22, blue: 0.28, alpha: 1))
            floor.roughness = 0.8
            let podium = ModelEntity(mesh: .generateCylinder(height: 0.1, radius: 3.2), materials: [floor])
            podium.position.y = -0.05
            anchor.addChild(podium)

            let sun = DirectionalLight()
            sun.light.intensity = 3500
            sun.look(at: .zero, from: [-3, 6, 4], relativeTo: nil)
            anchor.addChild(sun)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 40
            camera.look(at: [0, 0.4, 0], from: [4.2, 2.6, 5.2], relativeTo: nil)
            anchor.addChild(camera)

            subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.turntable.orientation *= simd_quatf(angle: Float(event.deltaTime) * 0.5, axis: [0, 1, 0])
                }
            }
        }

        func show(car: CarModel, livery: Livery) {
            guard shown?.car != car.id || shown?.livery != livery.id else { return }
            shown = (car.id, livery.id)
            loadTask?.cancel()
            loadTask = Task { [weak self] in
                guard let entity = try? await CarEntity.load(scale: 1, primary: livery.primary,
                                                             secondary: livery.secondary, accent: livery.accent,
                                                             model: car),
                      let self, !Task.isCancelled else { return }
                for child in self.turntable.children { child.removeFromParent() }
                self.turntable.addChild(entity.root)
            }
        }

        func stop() {
            subscription?.cancel()
            loadTask?.cancel()
        }
    }
}
