import SwiftUI
import RealityKit
import Combine

/// Общие настройки сцены для гонки и фона меню.
@MainActor
enum SceneSetup {
    static func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.55, green: 0.75, blue: 0.92, alpha: 1))
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        return view
    }

    static func makeSun() -> DirectionalLight {
        let sun = DirectionalLight()
        sun.light.intensity = 4000
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 200, depthBias: 3)
        sun.look(at: .zero, from: [-30, 60, 25], relativeTo: nil)
        return sun
    }
}

struct GameView: UIViewRepresentable {
    let track: TrackDefinition
    let state: GameState
    /// Увеличивается при нажатии «перезапуск».
    let restartToken: Int

    func makeCoordinator() -> GameController { GameController(definition: track, state: state) }
    func makeUIView(context: Context) -> ARView { context.coordinator.makeView() }
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.restartIfNeeded(token: restartToken)
    }
}

@MainActor
final class GameController: NSObject {
    private let state: GameState
    private let track: Track
    private var arView: ARView!
    private let camera = PerspectiveCamera()
    private let sun = SceneSetup.makeSun()
    private var car: CarEntity?
    private var follower: CarFollower
    private let fingerMarker: ModelEntity
    private var trailDots: [ModelEntity] = []
    private var updateSubscription: Cancellable?
    private var fittedSize: CGSize = .zero
    private var restartToken = 0

    private var finger: SIMD2<Float>?
    private var lastTouchLocation: CGPoint = .zero
    private var prevProgress = 0
    private var lapStarted = false
    private var passedHalfway = false
    private var lapTime: Double = 0
    private var hudTimer: Float = 0
    private var minimapTimer: Float = 0
    private var throttle: Float = 0
    private var wrongWayTimer: Float = 0

    /// Демо-режим для проверки без касаний: запуск с аргументом `-autopilot`.
    private let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    private var autopilotDistance: Float = -14
    /// `-reverse` — демо-палец ведёт машину против хода трассы (проверка «не того направления»).
    /// `-wobble` — демо-палец «дрожит», чтобы проверить сглаживание следа.
    private let autopilotWobble = ProcessInfo.processInfo.arguments.contains("-wobble")
    private let autopilotDirection: Float = ProcessInfo.processInfo.arguments.contains("-reverse") ? -1 : 1

    // Камера: фиксированный изометрический ракурс, следует за машиной.
    private let cameraFov: Float = 32
    private let cameraElevation: Float = 52 * .pi / 180
    /// Сколько метров земли видно по короткой стороне экрана.
    private let visibleWidth: Float = 110
    /// Курс камеры (вперёд = (sin, cos)) и курс, к которому она сейчас доворачивается.
    private var cameraYaw: Float = 0
    private var cameraGoalYaw: Float = 0
    /// Камера доворачивается, только если трасса впереди ушла от текущего вида больше чем на этот угол.
    private let cameraYawThreshold: Float = 18 * .pi / 180
    private var cameraDistance: Float = 100
    private var cameraTarget: SIMD3<Float> = .zero

    init(definition: TrackDefinition, state: GameState) {
        self.state = state
        track = Track(definition)
        let start = track.startPose
        follower = CarFollower(position: start.position, heading: start.heading)
        prevProgress = track.nearestIndex(start.position)
        state.carPosition = start.position

        var markerMat = UnlitMaterial(color: .white)
        markerMat.blending = .transparent(opacity: 0.55)
        let markerSize = definition.carScale / 1.5
        fingerMarker = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 1.3 * markerSize), materials: [markerMat])
        super.init()
    }

    func makeView() -> ARView {
        let view = SceneSetup.makeView()
        arView = view

        let anchor = AnchorEntity(world: .zero)
        view.scene.addAnchor(anchor)
        anchor.addChild(track.makeEntity())
        anchor.addChild(sun)

        let carScale = track.definition.carScale
        Task { @MainActor [weak self] in
            do {
                let car = try await CarEntity.load(scale: carScale)
                guard let self else { return }
                self.car = car
                anchor.addChild(car.root)
                car.update(position: self.follower.position, heading: self.follower.heading,
                           speed: 0, steer: 0, braking: false, dt: 0)
            } catch {
                print("Не удалось загрузить race_car.usdz: \(error)")
            }
            self?.state.isLoading = false
        }

        fingerMarker.isEnabled = false
        anchor.addChild(fingerMarker)

        var dotMat = UnlitMaterial(color: .white)
        dotMat.blending = .transparent(opacity: 0.7)
        let dotMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.22 * carScale / 1.5)
        for _ in 0..<250 {
            let dot = ModelEntity(mesh: dotMesh, materials: [dotMat])
            dot.isEnabled = false
            anchor.addChild(dot)
            trailDots.append(dot)
        }

        anchor.addChild(camera)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleTouch(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        view.addGestureRecognizer(press)

        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                self?.update(dt: Float(min(event.deltaTime, 1.0 / 20)))
            }
        }
        return view
    }

    /// Перезапуск гонки: машина на старт, круги и время — с нуля.
    func restartIfNeeded(token: Int) {
        guard token != restartToken else { return }
        restartToken = token
        let start = track.startPose
        follower = CarFollower(position: start.position, heading: start.heading)
        finger = nil
        prevProgress = track.nearestIndex(start.position)
        lapStarted = false
        passedHalfway = false
        lapTime = 0
        autopilotDistance = -14
        car?.update(position: follower.position, heading: follower.heading, speed: 0, steer: 0, braking: false, dt: 0)
        state.reset()
        wrongWayTimer = 0
        state.carPosition = follower.position
        state.isLoading = car == nil
        snapCamera()
    }

    // MARK: - Ввод

    @objc private func handleTouch(_ gesture: UILongPressGestureRecognizer) {
        let point = groundPoint(gesture.location(in: arView))
        switch gesture.state {
        case .began:
            guard let point else { return }
            finger = point
            lastTouchLocation = gesture.location(in: arView)
            follower.touchBegan(at: point)
            state.hasTouched = true
        case .changed:
            // Микродрожание неподвижного пальца не пересчитывает точку: иначе она «ехала» бы вместе с камерой.
            let location = gesture.location(in: arView)
            guard let point, hypot(location.x - lastTouchLocation.x, location.y - lastTouchLocation.y) >= 3 else { return }
            lastTouchLocation = location
            finger = point
        default:
            finger = nil
        }
    }

    /// Точка на плоскости земли (y = 0) под пальцем, в координатах (x, z).
    private func groundPoint(_ screen: CGPoint) -> SIMD2<Float>? {
        guard let ray = arView.ray(through: screen), ray.direction.y < -1e-4 else { return nil }
        let t = -ray.origin.y / ray.direction.y
        let p = ray.origin + ray.direction * t
        return SIMD2(p.x, p.z)
    }

    // MARK: - Игровой цикл

    private func update(dt: Float) {
        guard dt > 0 else { return }
        if arView.bounds.size != fittedSize, arView.bounds.width > 0 {
            configureCamera(for: arView.bounds.size)
        }

        if autopilot { driveAutopilot(dt: dt) }

        // Поребрик — часть трассы: скорость теряется, только когда машина целиком за ним.
        let offTrack = track.distanceFromCenterline(follower.position) > track.halfWidth + track.curbWidth + 0.3
        let oldSpeed = follower.speed
        follower.step(dt: dt, finger: finger, offTrack: offTrack)
        car?.update(position: follower.position, heading: follower.heading, speed: follower.speed,
                    steer: follower.steer, braking: follower.braking, dt: dt)
        updateEffects(oldSpeed: oldSpeed, offTrack: offTrack, dt: dt)
        updateWrongWay(dt: dt)

        updateCamera(dt: dt)
        updateMarkers()
        updateLaps(dt: dt)

        minimapTimer += dt
        if minimapTimer >= 1.0 / 30 {
            minimapTimer = 0
            state.carPosition = follower.position
            state.cameraYaw = cameraYaw
        }

        hudTimer += dt
        if hudTimer >= 0.1 {
            hudTimer = 0
            state.speedKmh = Int((follower.speed * 3.6).rounded())
            state.currentLapTime = lapTime
            state.offTrack = offTrack && follower.speed > 0.5
        }
    }

    /// Виртуальный палец едет по осевой линии с переменной скоростью (разгон → торможение до нуля → снова).
    private func driveAutopilot(dt: Float) {
        let t = Float(CACurrentMediaTime())
        let fingerSpeed = max(0, 60 * sin(t * 0.4))
        // Палец «отпускается», пока скорость в паузе, — как у игрока, который ведёт палец рывками.
        guard fingerSpeed > 0 else { finger = nil; return }
        if finger == nil {
            let here = track.nearestIndexDistance(follower.position)
            autopilotDistance = autopilotDirection > 0 ? max(autopilotDistance, here + 6) : here - 6
            finger = track.frame(atDistance: autopilotDistance).position
            follower.touchBegan(at: finger!)
            state.hasTouched = true
        }
        autopilotDistance += fingerSpeed * autopilotDirection * dt
        let frame = track.frame(atDistance: autopilotDistance)
        finger = frame.position
        if autopilotWobble {
            // Имитация дрожания руки: поперечная волна ~1 м с периодом ~6 м.
            let normal = SIMD2(frame.tangent.y, -frame.tangent.x)
            finger! += normal * (0.9 * sin(autopilotDistance * 1.05) + 0.4 * sin(autopilotDistance * 2.3))
        }
    }

    /// Выхлоп гуще при разгоне; дым из-под колёс — в резком повороте (близко к пределу сцепления) и при сносе.
    private func updateEffects(oldSpeed: Float, offTrack: Bool, dt: Float) {
        let accel = (follower.speed - oldSpeed) / dt
        throttle += (simd_clamp(accel / 12, 0, 1) - throttle) * (1 - exp(-dt / 0.15))
        var smoke: Float = 0
        if !offTrack && follower.speed > 12 {
            let cornering = (follower.lateralAccel / follower.grip - 0.75) / 0.25
            smoke = simd_clamp(max(cornering, follower.slide * 2), 0, 1)
        }
        car?.updateEffects(speed: follower.speed, throttle: throttle, smoke: smoke)
    }

    /// «Не то направление»: машина едет против хода трассы дольше секунды.
    private func updateWrongWay(dt: Float) {
        let tangent = track.tangents[track.nearestIndex(follower.position)]
        let along = simd_dot(SIMD2(sin(follower.course), cos(follower.course)), tangent)
        if follower.speed > 2 && along < -0.3 {
            wrongWayTimer = min(wrongWayTimer + dt, 1)
        } else if follower.speed > 2 && along > 0 || follower.speed <= 2 {
            wrongWayTimer = max(wrongWayTimer - dt * 3, 0)
        }
        let wrongWay = wrongWayTimer >= 1 || (state.wrongWay && wrongWayTimer > 0)
        if wrongWay != state.wrongWay { state.wrongWay = wrongWay }
    }

    private func updateMarkers() {
        if let finger {
            fingerMarker.isEnabled = true
            fingerMarker.position = SIMD3(finger.x, 0.07, finger.y)
        } else {
            fingerMarker.isEnabled = false
        }
        let path = follower.path
        for (i, dot) in trailDots.enumerated() {
            let idx = i * 2
            if idx < path.count {
                dot.isEnabled = true
                dot.position = SIMD3(path[idx].x, 0.06, path[idx].y)
            } else {
                dot.isEnabled = false
            }
        }
    }

    /// Прогресс — индекс ближайшей точки осевой линии (0 — линия старта).
    /// Круг засчитывается при пересечении старта по направлению гонки, если машина побывала на середине круга.
    private func updateLaps(dt: Float) {
        if lapStarted { lapTime += Double(dt) }
        let n = track.points.count
        let progress = track.nearestIndex(follower.position)
        defer { prevProgress = progress }

        if progress > n * 2 / 5 && progress < n * 3 / 5 { passedHalfway = true }

        let crossedForward = prevProgress > n * 3 / 4 && progress < n / 4
        let crossedBackward = prevProgress < n / 4 && progress > n * 3 / 4
        if crossedForward {
            if !lapStarted {
                lapStarted = true
                lapTime = 0
            } else if passedHalfway {
                state.laps += 1
                state.bestLap = min(state.bestLap ?? .infinity, lapTime)
                LapRecords.recordLap(track.definition.id, time: lapTime)
                lapTime = 0
            }
            passedHalfway = false
        } else if crossedBackward {
            passedHalfway = false
        }
    }

    /// Дистанция камеры подбирается так, чтобы по короткой стороне экрана было видно `visibleWidth` метров.
    private func configureCamera(for size: CGSize) {
        fittedSize = size
        camera.camera.fieldOfViewInDegrees = cameraFov
        let aspect = Float(size.width / size.height)
        let tanV = tan(cameraFov * .pi / 180 / 2)
        let visibleHeight = aspect < 1 ? visibleWidth / aspect : visibleWidth
        cameraDistance = visibleHeight * sin(cameraElevation) / (2 * tanV)
        sun.shadow?.maximumDistance = cameraDistance + 120
        snapCamera()
    }

    private var cameraForward: SIMD2<Float> { SIMD2(sin(cameraYaw), cos(cameraYaw)) }

    private var cameraBack: SIMD3<Float> {
        let f = cameraForward
        return SIMD3(-f.x * cos(cameraElevation), sin(cameraElevation), -f.y * cos(cameraElevation))
    }

    /// Расстояние по трассе до машины (ближайшая точка осевой).
    private var carTrackDistance: Float { track.nearestIndexDistance(follower.position) }

    /// Куда в целом уходит трасса на ближайших ~150 м: средняя из хорд от машины к точкам впереди.
    /// Хорды, а не касательные, — так учитывается, куда трасса реально сместится на экране,
    /// а мелкие изгибы и шиканы почти не влияют.
    private func trackAheadYaw() -> Float {
        let s = carTrackDistance
        let base = track.frame(atDistance: s).position
        var sum = SIMD2<Float>(repeating: 0)
        for d in stride(from: Float(30), through: 150, by: 30) {
            let chord = track.frame(atDistance: s + d).position - base
            sum += chord / max(simd_length(chord), 1)
        }
        return atan2(sum.x, sum.y)
    }

    /// Куда смотреть: на точку трассы впереди машины (по самой трассе, а не по прямой),
    /// так в кадре оказывается именно будущий участок, а машина — в нижней части экрана.
    private func cameraGoal() -> SIMD3<Float> {
        let s = carTrackDistance
        let lead = min(60 + follower.speed * 0.3, 95)
        let lateral = follower.position - track.frame(atDistance: s).position
        let p = track.frame(atDistance: s + lead).position + lateral * 0.5
        return SIMD3(p.x, 0, p.y)
    }

    private func snapCamera() {
        cameraYaw = trackAheadYaw()
        cameraGoalYaw = cameraYaw
        state.cameraYaw = cameraYaw
        cameraTarget = cameraGoal()
        camera.look(at: cameraTarget, from: cameraTarget + cameraBack * cameraDistance, relativeTo: nil)
    }

    /// Поворот камеры: она смотрит туда, куда уходит трасса впереди, а не куда повёрнута машина.
    /// Пока палец на экране, поворот медленнее, чтобы нарисованная линия не «уезжала» из-под пальца.
    private func updateCameraYaw(dt: Float) {
        let ahead = trackAheadYaw()
        if abs(wrapAngle(ahead - cameraGoalYaw)) > cameraYawThreshold {
            cameraGoalYaw = ahead
        }
        let diff = wrapAngle(cameraGoalYaw - cameraYaw)
        let maxRate: Float = (finger == nil ? 90 : 35) * .pi / 180
        let smooth = diff * (1 - exp(-dt / 0.5))
        cameraYaw = wrapAngle(cameraYaw + simd_clamp(smooth, -maxRate * dt, maxRate * dt))
    }

    /// Сдвиг камеры, нужный, чтобы точка `world` оказалась внутри области экрана `zone` (доли экрана).
    private func shiftToKeep(_ world: SIMD2<Float>, in zone: CGRect) -> SIMD3<Float>? {
        let point = SIMD3(world.x, 0, world.y)
        guard let screen = arView.project(point) else { return nil }
        let b = arView.bounds
        let rect = CGRect(x: b.width * zone.minX, y: b.height * zone.minY,
                          width: b.width * zone.width, height: b.height * zone.height)
        let clamped = CGPoint(x: min(max(screen.x, rect.minX), rect.maxX), y: min(max(screen.y, rect.minY), rect.maxY))
        guard clamped != screen, let ground = groundPoint(clamped) else { return nil }
        return point - SIMD3(ground.x, 0, ground.y)
    }

    /// Без пальца камера плавно следует за участком трассы впереди машины.
    /// С пальцем камера не едет сама (иначе точка под пальцем «уезжала» бы вместе с ней и машина не
    /// останавливалась), а только сдвигается, чтобы: 1) трасса на ~110 м вперёд оставалась в кадре,
    /// 2) машина держалась в нижней трети экрана. Второе важнее, поэтому применяется последним.
    private func updateCamera(dt: Float) {
        updateCameraYaw(dt: dt)
        if finger == nil {
            cameraTarget += (cameraGoal() - cameraTarget) * (1 - exp(-dt / 0.3))
        } else {
            let ahead = track.frame(atDistance: carTrackDistance + 110).position
            if let shift = shiftToKeep(ahead, in: CGRect(x: 0.1, y: 0.08, width: 0.8, height: 0.8)) {
                cameraTarget += shift * (1 - exp(-dt / 0.25))
            }
            camera.look(at: cameraTarget, from: cameraTarget + cameraBack * cameraDistance, relativeTo: nil)
            if let shift = shiftToKeep(follower.position, in: CGRect(x: 0.12, y: 0.66, width: 0.76, height: 0.22)) {
                cameraTarget += shift * (1 - exp(-dt / 0.12))
            }
        }
        camera.look(at: cameraTarget, from: cameraTarget + cameraBack * cameraDistance, relativeTo: nil)
    }
}
