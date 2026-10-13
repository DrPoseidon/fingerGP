import SwiftUI
import RealityKit
import Combine

/// Фон меню: «дрон» плавно летит за машиной, которая едет по трассам игры.
/// Каждые `segmentDuration` секунд — смена трассы через затемнение.
struct FlyoverView: UIViewRepresentable {
    func makeCoordinator() -> FlyoverController { FlyoverController() }
    func makeUIView(context: Context) -> UIView { context.coordinator.makeView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
final class FlyoverController {
    private let order: [TrackID] = [.monza, .nordschleife, .spa, .oval]
    private var orderIndex = 0
    private var track: Track
    private var arView: ARView!
    private let fadeView = UIView()
    private let anchor = AnchorEntity(world: .zero)
    private var trackEntity: Entity?
    private let camera = PerspectiveCamera()
    private var car: CarEntity?
    private var updateSubscription: Cancellable?

    private var distance: Float = 0
    private var speed: Float = 30
    private var cameraPosition: SIMD3<Float> = .zero
    private var cameraTarget: SIMD3<Float> = .zero
    private var timeOnTrack: Float = 0
    private var switching = false
    /// Сколько кадров уже отрисовано — затемнение снимается сразу после первых кадров, не дожидаясь машины.
    private var renderedFrames = 0

    private let segmentDuration: Float = 22
    private let grip: Float = 30            // м/с² — машина на фоне сбрасывает скорость в поворотах
    private let maxSpeed: Float = 60

    init() {
        track = Track(TrackDefinition.get(order[0]))
    }

    func makeView() -> UIView {
        let container = UIView()
        let view = SceneSetup.makeView()
        arView = view
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(view)

        fadeView.backgroundColor = UIColor(red: 0.039, green: 0.047, blue: 0.063, alpha: 1)
        fadeView.alpha = 1
        fadeView.frame = container.bounds
        fadeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fadeView.isUserInteractionEnabled = false
        container.addSubview(fadeView)

        view.scene.addAnchor(anchor)
        anchor.addChild(SceneSetup.makeSun())
        camera.camera.fieldOfViewInDegrees = 55
        anchor.addChild(camera)
        showTrack(track)

        Task { @MainActor [weak self] in
            guard let car = try? await CarEntity.load(scale: 2), let self else { return }
            self.car = car
            self.anchor.addChild(car.root)
        }

        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                self?.update(dt: Float(min(event.deltaTime, 1.0 / 20)))
            }
        }
        return container
    }

    private func showTrack(_ newTrack: Track) {
        trackEntity?.removeFromParent()
        track = newTrack
        let entity = newTrack.makeEntity()
        anchor.addChild(entity)
        trackEntity = entity
        distance = 0
        speed = 30
        timeOnTrack = 0
        snapCamera()
    }

    private func update(dt: Float) {
        guard dt > 0 else { return }

        renderedFrames += 1
        if renderedFrames == 3 {
            UIView.animate(withDuration: 0.6) { self.fadeView.alpha = 0 }
        }
        // Пока модель машины грузится, она «стоит на старте» — камера не улетает вперёд от пустого места.
        guard car != nil else { return }

        // Скорость машины ограничена кривизной впереди: в поворотах она замедляется.
        let ahead = track.frame(atDistance: distance + 15).tangent
        let here = track.frame(atDistance: distance).tangent
        let bend = abs(wrapAngle(atan2(ahead.x, ahead.y) - atan2(here.x, here.y))) / 15
        let target = min(maxSpeed, sqrt(grip / max(bend, 1e-4)))
        speed += simd_clamp(target - speed, -25 * dt, 12 * dt)
        distance += speed * dt

        let (position, tangent) = track.frame(atDistance: distance)
        let next = track.frame(atDistance: distance + 6).tangent
        let heading = atan2(tangent.x, tangent.y)
        let steer = simd_clamp(atan(2.34 * wrapAngle(atan2(next.x, next.y) - heading) / 6), -0.4, 0.4)
        car?.update(position: position, heading: heading, speed: speed, steer: steer, braking: target < speed - 3, dt: dt)

        // Камера-«дрон»: позади и сбоку от машины, с плавным запаздыванием.
        let (desiredPosition, desiredTarget) = cameraGoal()
        cameraPosition += (desiredPosition - cameraPosition) * (1 - exp(-dt / 0.9))
        cameraTarget += (desiredTarget - cameraTarget) * (1 - exp(-dt / 0.5))
        camera.look(at: cameraTarget, from: cameraPosition, relativeTo: nil)

        timeOnTrack += dt
        if timeOnTrack > segmentDuration && !switching { switchTrack() }
    }

    private func cameraGoal() -> (SIMD3<Float>, SIMD3<Float>) {
        // Позиция камеры берётся по сглаженной точке трассы позади машины — так пролёт плавнее.
        let behind = track.frame(atDistance: distance - 30)
        let side = SIMD2(behind.tangent.y, -behind.tangent.x)
        let p = behind.position + side * 16
        let look = track.frame(atDistance: distance + 12).position
        return (SIMD3(p.x, 15, p.y), SIMD3(look.x, 0, look.y))
    }

    private func snapCamera() {
        (cameraPosition, cameraTarget) = cameraGoal()
        camera.look(at: cameraTarget, from: cameraPosition, relativeTo: nil)
    }

    private func switchTrack() {
        switching = true
        UIView.animate(withDuration: 0.7, animations: { self.fadeView.alpha = 1 }, completion: { _ in
            self.orderIndex = (self.orderIndex + 1) % self.order.count
            self.showTrack(Track(TrackDefinition.get(self.order[self.orderIndex])))
            UIView.animate(withDuration: 0.9, delay: 0.1, animations: { self.fadeView.alpha = 0 }, completion: { _ in
                self.switching = false
            })
        })
    }
}
