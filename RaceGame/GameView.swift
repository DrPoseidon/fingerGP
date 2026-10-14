import SwiftUI
import RealityKit
import Combine
import os

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
    static func dismantleUIView(_ uiView: ARView, coordinator: GameController) { coordinator.shutdown() }
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
    private var lapTimer: LapTimer
    /// Лучший круг для призрака, его сектора и запись текущего круга.
    private var ghost: Ghost?
    private var bestSplits: [Double]?
    private var recording = Ghost()
    private var ghostCar: GhostCar?
    private var deltaTimer: Float = 0
    // Возврат на трассу (настройка): сколько секунд машина за поребриком и где съехала с трассы.
    private let resetToTrack = RaceSettings.resetToTrack
    /// С возвратом на трассу выезд наказывается штрафом, а не незасчётом круга: срезать всё равно не выйдет.
    private static var invalidatesOnOffTrack: Bool { RaceSettings.offTrackRule == .invalidate && !RaceSettings.resetToTrack }
    private var offTrackStreak: Float = 0
    private var lastOnTrackDistance: Float = 0
    private var resetting = false
    /// После возврата на трассу текущее касание игнорируется, пока палец не поднимут.
    private var touchSuspended = false
    private let fadeView = UIView()
    private var wasOffTrack = false
    private var bannerTimer: Float = 0
    private var hudTimer: Float = 0
    private var minimapTimer: Float = 0
    private var throttle: Float = 0
    private let audio = RaceAudio()
    private let haptics = RaceHaptics()
    private var wrongWayTimer: Float = 0

    /// Старт с хода (настройка): машина сама разгоняется по осевой к линии старта, пока гаснут три красных огня.
    /// Огни привязаны к расстоянию до линии: за `greenDistance` метров (~3 с) загорается зелёный, и первое
    /// касание забирает управление — есть время подхватить машину до линии. Время круга, как обычно, — с линии старта.
    private struct RunUp {
        /// Сколько красных огней ещё горит; `green` — загорелся зелёный, управление можно забрать.
        var redLights = 3
        var green = false
        /// Где на осевой виртуальный палец (отрицательно — до линии старта) и с какой скоростью он едет.
        var fingerDistance: Float
        var fingerSpeed: Float
        var launched = false
    }
    private var runUp: RunUp?
    private var lightsTimer: Float = 0
    private static let runUpDistance: Float = 340
    /// Скорость на разгоне: в начале и крейсерская (~180 км/ч — средняя, не максимальная).
    private static let runUpStartSpeed: Float = 35
    private static let runUpCruiseSpeed: Float = 50
    /// На каком расстоянии до линии гаснут красные огни (по очереди) и загорается зелёный — по ~0.9 с.
    private static let redOffDistances: [Float] = [285, 240, 195]
    private static let greenDistance: Float = 150

    /// Демо-режим для проверки без касаний: запуск с аргументом `-autopilot`.
    private let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    private var autopilotDistance: Float = -14
    /// `-reverse` — демо-палец ведёт машину против хода трассы (проверка «не того направления»).
    /// `-wobble` — демо-палец «дрожит», чтобы проверить сглаживание следа.
    private let autopilotWobble = ProcessInfo.processInfo.arguments.contains("-wobble")
    /// `-drift` — раз за круг демо-палец уводит машину на 16 м в сторону, на траву (проверка выездов).
    private let autopilotDrift = ProcessInfo.processInfo.arguments.contains("-drift")
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
        let start = GameController.spawnPose(track)
        follower = CarFollower(position: start.position, heading: start.heading)
        lapTimer = LapTimer(pointCount: track.points.count, startProgress: track.nearestIndex(start.position))
        lapTimer.invalidatesOnOffTrack = GameController.invalidatesOnOffTrack
        lastOnTrackDistance = track.nearestIndexDistance(start.position)
        if ProcessInfo.processInfo.arguments.contains("-resetRecords") { LapRecords.reset(definition.id) }
        ghost = Ghost.load(for: definition.id)
        bestSplits = LapRecords.bestSplits(definition.id)
        state.carPosition = start.position

        var markerMat = UnlitMaterial(color: .white)
        markerMat.blending = .transparent(opacity: 0.55)
        let markerSize = definition.carScale / 1.5
        fingerMarker = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 1.3 * markerSize), materials: [markerMat])
        super.init()
        prepareRunUp()
    }

    /// С разгоном — машина стоит за `runUpDistance` до линии (на коротких трассах ближе), иначе — сразу за линией.
    private static func spawnPose(_ track: Track) -> (position: SIMD2<Float>, heading: Float) {
        guard RaceSettings.rollingStart else { return track.startPose }
        let f = track.frame(atDistance: -runUpDistance(track))
        return (f.position, atan2(f.tangent.x, f.tangent.y))
    }

    /// На коротких трассах разгон короче — машина не должна стоять дальше середины круга от линии.
    private static func runUpDistance(_ track: Track) -> Float { min(runUpDistance, track.length * 0.5) }

    private func prepareRunUp() {
        guard RaceSettings.rollingStart else { runUp = nil; return }
        runUp = RunUp(fingerDistance: -GameController.runUpDistance(track), fingerSpeed: 0)
        state.startLights = .red(3)
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
        audio.start()

        let ghostCar = GhostCar(scale: carScale)
        ghostCar.root.isEnabled = false
        anchor.addChild(ghostCar.root)
        self.ghostCar = ghostCar

        // Затемнение при возврате на трассу: только сцена, HUD SwiftUI остаётся видимым поверх.
        fadeView.backgroundColor = .black
        fadeView.alpha = 0
        fadeView.isUserInteractionEnabled = false
        fadeView.frame = view.bounds
        fadeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(fadeView)

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
        let start = GameController.spawnPose(track)
        follower = CarFollower(position: start.position, heading: start.heading)
        finger = nil
        lapTimer = LapTimer(pointCount: track.points.count, startProgress: track.nearestIndex(start.position))
        lapTimer.invalidatesOnOffTrack = GameController.invalidatesOnOffTrack
        lastOnTrackDistance = track.nearestIndexDistance(start.position)
        offTrackStreak = 0
        resetting = false
        touchSuspended = false
        fadeView.layer.removeAllAnimations()
        fadeView.alpha = 0
        recording = Ghost()
        ghostCar?.root.isEnabled = false
        deltaTimer = 0
        bannerTimer = 0
        autopilotDistance = -14
        car?.update(position: follower.position, heading: follower.heading, speed: 0, steer: 0, braking: false, dt: 0)
        state.reset()
        wrongWayTimer = 0
        state.carPosition = follower.position
        state.isLoading = car == nil
        lightsTimer = 0
        prepareRunUp()
        snapCamera()
    }

    // MARK: - Ввод

    @objc private func handleTouch(_ gesture: UILongPressGestureRecognizer) {
        let point = groundPoint(gesture.location(in: arView))
        // Во время возврата на трассу касания не принимаются; после — нужно новое касание.
        if resetting { finger = nil; return }
        // Во время отсчёта машина едет сама; после «Старт!» первое касание забирает управление.
        var phase = gesture.state
        if let runUp {
            guard runUp.green, phase == .began || phase == .changed else { return }
            self.runUp = nil
            phase = .began
        }
        switch phase {
        case .began:
            guard let point else { return }
            touchSuspended = false
            finger = point
            lastTouchLocation = gesture.location(in: arView)
            follower.touchBegan(at: point)
            state.markTouched()
        case .changed:
            if touchSuspended { return }
            // Микродрожание неподвижного пальца не пересчитывает точку: иначе она «ехала» бы вместе с камерой.
            let location = gesture.location(in: arView)
            guard let point, hypot(location.x - lastTouchLocation.x, location.y - lastTouchLocation.y) >= 3 else { return }
            lastTouchLocation = location
            finger = point
        default:
            finger = nil
            touchSuspended = false
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

        if runUp != nil {
            driveRunUp(dt: dt)
        } else if autopilot {
            driveAutopilot(dt: dt)
        }

        // Поребрик — часть трассы: скорость теряется, только когда машина целиком за ним.
        let fromCenter = track.distanceFromCenterline(follower.position)
        let offTrack = fromCenter > track.halfWidth + track.curbWidth + 0.3
        // На поребрике — когда колёса одной стороны на нём (центр машины ближе ~0.4 м к краю асфальта).
        let onCurb = !offTrack && fromCenter > track.halfWidth - 0.4
        if offTrack {
            offTrackStreak += dt
        } else {
            offTrackStreak = 0
            lastOnTrackDistance = track.nearestIndexDistance(follower.position)
        }
        if resetToTrack && !resetting && offTrackStreak > Float(RaceSettings.resetDelay) {
            beginResetToTrack()
        }
        if offTrack != wasOffTrack {
            wasOffTrack = offTrack
            GameController.lapLog.debug("offTrack=\(offTrack) fromCenter=\(fromCenter) lapTime=\(self.lapTimer.lapTime)")
        }
        let oldSpeed = follower.speed
        follower.step(dt: dt, finger: finger, offTrack: offTrack)
        car?.update(position: follower.position, heading: follower.heading, speed: follower.speed,
                    steer: follower.steer, braking: follower.braking, dt: dt)
        updateEffects(oldSpeed: oldSpeed, offTrack: offTrack, onCurb: onCurb, dt: dt)
        updateWrongWay(dt: dt)

        updateCamera(dt: dt)
        updateMarkers()
        // Пока идёт возврат на трассу, выезд не копится в «срезку» — за него будет штраф.
        updateLaps(dt: dt, offTrack: offTrack && !resetting)
        updateGhost(dt: dt)

        minimapTimer += dt
        if minimapTimer >= 1.0 / 30 {
            minimapTimer = 0
            state.carPosition = follower.position
            state.cameraYaw = cameraYaw
            state.ghostPosition = ghostCar?.root.isEnabled == true
                ? SIMD2(ghostCar!.root.position.x, ghostCar!.root.position.z) : nil
        }

        hudTimer += dt
        if hudTimer >= 0.1 {
            hudTimer = 0
            state.speedKmh = Int((follower.speed * 3.6).rounded())
            state.currentLapTime = lapTimer.lapTime
            state.offTrack = offTrack && follower.speed > 0.5
        }
        if deltaTimer > 0 {
            deltaTimer -= dt
            if deltaTimer <= 0 { state.delta = nil }
        }
        if bannerTimer > 0 {
            bannerTimer -= dt
            if bannerTimer <= 0 { state.banner = nil }
        }
        if lightsTimer > 0 {
            lightsTimer -= dt
            if lightsTimer <= 0 { state.startLights = nil }
        }
    }

    /// Разгон к линии старта: виртуальный палец едет по осевой впереди машины с крейсерской скоростью,
    /// медленнее — если впереди поворот. Разгон начинается, когда машина загружена.
    private func driveRunUp(dt: Float) {
        guard var r = runUp, car != nil else { return }
        if !r.launched {
            r.launched = true
            let speed = min(GameController.runUpStartSpeed, safeSpeed(atDistance: r.fingerDistance))
            follower.launch(speed: speed)
            r.fingerSpeed = speed
            r.fingerDistance += 6 + speed * 0.4
            finger = track.frame(atDistance: r.fingerDistance).position
            follower.touchBegan(at: finger!)
        }

        // Огни: сколько метров машине до линии старта (до линии — положительно).
        let here = track.nearestIndexDistance(follower.position)
        let toLine = here > track.length / 2 ? track.length - here : -here
        if !r.green {
            let lit = GameController.redOffDistances.filter { toLine <= $0 }.count
            let red = 3 - lit
            if toLine <= GameController.greenDistance {
                r.green = true
                state.startLights = .green
                audio.play(.go)
                haptics.countdown(go: true)
                lightsTimer = 1.2
            } else if red < r.redLights {
                r.redLights = red
                state.startLights = .red(red)
                audio.play(.countdown)
                haptics.countdown(go: false)
            }
        }

        r.fingerSpeed = min(r.fingerSpeed + 15 * dt, GameController.runUpCruiseSpeed,
                            safeSpeed(atDistance: r.fingerDistance))
        r.fingerDistance += r.fingerSpeed * dt
        finger = track.frame(atDistance: r.fingerDistance).position
        runUp = r

        // Демо-палец забирает управление на зелёный. Игрок так и не коснулся экрана — машину
        // отпускают, как только погаснут зелёные огни.
        if r.green && (autopilot || lightsTimer <= 0) {
            runUp = nil
            finger = nil
        }
    }

    /// Скорость, с которой виртуальный палец успеет оттормозиться перед поворотами на ближайших 250 м.
    private func safeSpeed(atDistance s: Float) -> Float {
        var limit = follower.maxSpeed
        var d: Float = 0
        while d < 250 {
            let a = track.frame(atDistance: s + d - 2.5).tangent
            let b = track.frame(atDistance: s + d + 2.5).tangent
            let curvature = abs(atan2(a.x * b.y - a.y * b.x, simd_dot(a, b))) / 5
            if curvature > 1e-4 {
                let corner = (0.8 * follower.grip / curvature).squareRoot()
                limit = min(limit, (corner * corner + follower.brakeDecel * d).squareRoot())
            }
            d += 5
        }
        return limit
    }

    /// Виртуальный палец едет по осевой линии с переменной скоростью (разгон → торможение до нуля → снова).
    private func driveAutopilot(dt: Float) {
        if resetting { finger = nil; return }
        let t = Float(CACurrentMediaTime())
        let fingerSpeed = max(0, 60 * sin(t * 0.4))
        // Палец «отпускается», пока скорость в паузе, — как у игрока, который ведёт палец рывками.
        guard fingerSpeed > 0 else { finger = nil; return }
        if finger == nil {
            let here = track.nearestIndexDistance(follower.position)
            autopilotDistance = autopilotDirection > 0 ? max(autopilotDistance, here + 6) : here - 6
            finger = track.frame(atDistance: autopilotDistance).position
            follower.touchBegan(at: finger!)
            state.markTouched()
        }
        autopilotDistance += fingerSpeed * autopilotDirection * dt
        let frame = track.frame(atDistance: autopilotDistance)
        finger = frame.position
        if autopilotWobble {
            // Имитация дрожания руки: поперечная волна ~1 м с периодом ~6 м.
            let normal = SIMD2(frame.tangent.y, -frame.tangent.x)
            finger! += normal * (0.9 * sin(autopilotDistance * 1.05) + 0.4 * sin(autopilotDistance * 2.3))
        }
        if autopilotDrift {
            let along = autopilotDistance - (autopilotDistance / track.length).rounded(.down) * track.length
            if along > track.length * 0.3 && along < track.length * 0.3 + 60 {
                finger! += SIMD2(frame.tangent.y, -frame.tangent.x) * 16
            }
        }
    }

    /// Выхлоп гуще при разгоне; дым из-под колёс — в резком повороте (близко к пределу сцепления) и при сносе.
    private func updateEffects(oldSpeed: Float, offTrack: Bool, onCurb: Bool, dt: Float) {
        let accel = (follower.speed - oldSpeed) / dt
        throttle += (simd_clamp(accel / 12, 0, 1) - throttle) * (1 - exp(-dt / 0.15))
        var smoke: Float = 0
        if !offTrack && follower.speed > 12 {
            let cornering = (follower.lateralAccel / follower.grip - 0.75) / 0.25
            smoke = simd_clamp(max(cornering, follower.slide * 2), 0, 1)
        }
        car?.updateEffects(speed: follower.speed, throttle: throttle, smoke: smoke)

        audio.syncMute()
        audio.update(speed: follower.speed, maxSpeed: follower.maxSpeed, throttle: throttle,
                     onCurb: onCurb, onGrass: offTrack)
        haptics.update(speed: follower.speed, onCurb: onCurb, onGrass: offTrack, dt: dt)
    }

    /// Остановить звук при уходе с экрана гонки.
    func shutdown() {
        audio.stop()
        updateSubscription?.cancel()
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
        if wrongWay != state.wrongWay {
            state.wrongWay = wrongWay
            if wrongWay { haptics.wrongWay() }
        }
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

    /// Зачёт круга, сектора и запись круга для призрака.
    private func updateLaps(dt: Float, offTrack: Bool) {
        let events = lapTimer.update(progress: track.nearestIndex(follower.position), offTrack: offTrack, dt: Double(dt))
        if lapTimer.isRunning {
            // Запись положения 20 раз в секунду (по времени круга).
            while Double(recording.samples.count) * Ghost.interval <= lapTimer.lapTime {
                recording.samples.append(SIMD4(follower.position.x, follower.position.y, follower.heading, follower.speed))
            }
        }

        for event in events {
            GameController.lapLog.info("\(String(describing: event), privacy: .public) lapTime=\(self.lapTimer.lapTime) offTrack=\(offTrack) fromCenter=\(self.track.distanceFromCenterline(self.follower.position))")
            switch event {
            case .lapStarted:
                recording = Ghost()
                state.lapInvalid = false
            case .sector(let index, let time):
                if lapTimer.isValid, let best = bestSplits, index < best.count {
                    showDelta(time - best[index], label: "S\(index + 1)")
                    haptics.sector()
                }
            case .invalidated:
                state.lapInvalid = true
                haptics.wrongWay()
            case .lapFinished(let time, let splits, let valid):
                if valid {
                    finishLap(time: time, splits: splits)
                } else {
                    showBanner("Круг не засчитан", good: false)
                }
            }
        }
    }

    private static let lapLog = Logger(subsystem: "com.example.RaceGame", category: "laps")

    private func finishLap(time: Double, splits: [Double]) {
        let id = track.definition.id
        let previousBest = LapRecords.bestLap(id)
        state.laps += 1
        state.bestLap = min(state.bestLap ?? .infinity, time)
        if let previousBest { showDelta(time - previousBest, label: "Круг") }

        let isRecord = LapRecords.recordLap(id, time: time, splits: splits, ghost: recording)
        if isRecord {
            ghost = recording
            bestSplits = splits
        }
        // Первый круг на трассе — просто круг; рекорд — когда побит прежний.
        let celebrate = isRecord && previousBest != nil
        if celebrate { showBanner("Новый рекорд!", good: true) }
        audio.play(celebrate ? .record : .lap)
        haptics.lap(record: celebrate)
    }

    /// Призрак повторяет лучший круг синхронно с текущим: в одно и то же время от старта круга.
    private func updateGhost(dt: Float) {
        guard let ghostCar else { return }
        guard lapTimer.isRunning, let pose = ghost?.pose(at: lapTimer.lapTime) else {
            ghostCar.root.isEnabled = false
            return
        }
        ghostCar.root.isEnabled = true
        ghostCar.update(position: pose.position, heading: pose.heading)
    }

    /// Возврат на трассу: сцена затемняется, машина ставится на осевую линию там, где съехала,
    /// стоя на месте и по направлению трассы; к кругу добавляется штраф.
    private func beginResetToTrack() {
        resetting = true
        touchSuspended = true
        finger = nil
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseIn], animations: {
            self.fadeView.alpha = 1
        }, completion: { _ in
            guard self.resetting else { return }
            self.respawnOnTrack()
            UIView.animate(withDuration: 0.5, delay: 0.15, options: [.curveEaseOut], animations: {
                self.fadeView.alpha = 0
            }, completion: { _ in
                self.resetting = false
            })
        })
    }

    private func respawnOnTrack() {
        let frame = track.frame(atDistance: lastOnTrackDistance)
        let heading = atan2(frame.tangent.x, frame.tangent.y)
        follower = CarFollower(position: frame.position, heading: heading)
        car?.update(position: frame.position, heading: heading, speed: 0, steer: 0, braking: false, dt: 0)
        offTrackStreak = 0
        lapTimer.forgiveCurrentExcursion()
        lapTimer.addPenalty(RaceSettings.resetPenalty)
        GameController.lapLog.info("respawn at distance=\(self.lastOnTrackDistance) lapTime=\(self.lapTimer.lapTime)")
        showBanner(String(format: "Возврат на трассу · +%.0f с", RaceSettings.resetPenalty), good: false,
                   icon: "arrow.uturn.backward.circle.fill")
        snapCamera()
    }

    private func showDelta(_ delta: Double, label: String) {
        state.delta = delta
        state.deltaLabel = label
        deltaTimer = 3
    }

    private func showBanner(_ text: String, good: Bool, icon: String? = nil) {
        state.banner = text
        state.bannerIsGood = good
        state.bannerIcon = icon ?? (good ? "trophy.fill" : "xmark.octagon.fill")
        bannerTimer = 2.5
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
