import SwiftUI
import RealityKit
import Combine
import os

@MainActor
final class GameController: NSObject {
    let state: GameState
    let track: Track
    var arView: ARView!
    let camera = PerspectiveCamera()
    let sun = SceneSetup.makeSun()
    var car: CarEntity?
    var follower: CarFollower
    let fingerMarker: ModelEntity
    var trailDots: [ModelEntity] = []
    var updateSubscription: Cancellable?
    var fittedSize: CGSize = .zero
    var restartToken = 0

    var finger: SIMD2<Float>?
    var lastTouchLocation: CGPoint = .zero
    var lapTimer: LapTimer

    /// Машина и ливрея из гаража.
    let carModel = Wallet.shared.car
    let livery = Wallet.shared.livery
    var coinTimer: Float = 0

    // Гонка против соперников (режим «Гонка»).
    let mode: GameMode
    let session: RaceSession?
    /// Время с загрузки до зелёного: огни гаснут по секунде, потом зелёный. nil — гонка уже идёт.
    var raceLightsTime: Float? = 0
    var raceLaps = 0
    var racePenalty: Double = 0
    var raceFinished = false
    /// После финиша машину ведёт автопилот: виртуальный палец по осевой со спокойной скоростью.
    var cooldown: VirtualFinger?
    /// Счётчик кадров (настройка «Показывать FPS»): кадры и самый долгий кадр за полсекунды.
    let showFPS = RaceSettings.showFPS
    var fpsFrames = 0
    var fpsWindowStart: CFTimeInterval = 0
    var fpsLastFrame: CFTimeInterval = 0
    var fpsWorst: CFTimeInterval = 0
    /// Дистанция игрока от линии старта (на решётке — отрицательная) и индекс ближайшей точки.
    var playerProgress: Float = 0
    var playerIndex = 0
    var hitCooldown: Float = 0
    var isRace: Bool { mode == .race }
    /// До зелёного в гонке касания не принимаются.
    var raceWaiting: Bool { isRace && raceLightsTime != nil }
    /// Лучший круг для призрака, его сектора и запись текущего круга.
    var ghost: Ghost?
    var bestSplits: [Double]?
    var recording = Ghost()
    var ghostCar: GhostCar?
    /// Призрак медали-цели (следующей не полученной) — в её цвете.
    var medalGhostCar: GhostCar?
    var medalTarget: Medal?
    var medalRun: MedalRun?
    var anchor: AnchorEntity?
    var deltaTimer: Float = 0
    // Возврат на трассу (настройка): сколько секунд машина за поребриком и где съехала с трассы.
    let resetToTrack = RaceSettings.resetToTrack
    static var invalidatesOnOffTrack: Bool { RaceSettings.offTrackRule == .invalidate }
    var offTrackStreak: Float = 0
    var lastOnTrackDistance: Float = 0
    var resetting = false
    /// После возврата на трассу текущее касание игнорируется, пока палец не поднимут.
    var touchSuspended = false
    let fadeView = UIView()
    var wasOffTrack = false
    var bannerTimer: Float = 0
    var hudTimer: Float = 0
    var minimapTimer: Float = 0
    var throttle: Float = 0
    let audio = RaceAudio()
    let haptics = RaceHaptics()
    var wrongWayTimer: Float = 0
    /// Сколько секунд машина стоит без пальца на экране; дольше `idleHintDelay` — подсказка жестом.
    var idleTime: Float = 0
    let idleHintDelay: Float = 1.5

    /// Старт с хода (настройка): машина сама разгоняется по осевой к линии старта, пока гаснут три красных огня.
    /// Огни привязаны к расстоянию до линии: за `greenDistance` метров (~3 с) загорается зелёный, и первое
    /// касание забирает управление — есть время подхватить машину до линии. Время круга, как обычно, — с линии старта.
    struct RunUp {
        /// Сколько красных огней ещё горит; `green` — загорелся зелёный, управление можно забрать.
        var redLights = 3
        var green = false
        /// Где на осевой виртуальный палец (отрицательно — до линии старта) и с какой скоростью он едет.
        var fingerDistance: Float
        var fingerSpeed: Float
        var launched = false
    }
    var runUp: RunUp?
    var lightsTimer: Float = 0
    static let runUpDistance: Float = 340
    /// Скорость на разгоне: в начале и крейсерская (~180 км/ч — средняя, не максимальная).
    static let runUpStartSpeed: Float = 35
    static let runUpCruiseSpeed: Float = 50
    /// На каком расстоянии до линии гаснут красные огни (по очереди) и загорается зелёный — по ~0.9 с.
    static let redOffDistances: [Float] = [285, 240, 195]
    static let greenDistance: Float = 150

    /// Демо-режим для проверки без касаний: запуск с аргументом `-autopilot`.
    let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    var autopilotDistance: Float = -14
    /// `-reverse` — демо-палец ведёт машину против хода трассы (проверка «не того направления»).
    /// `-wobble` — демо-палец «дрожит», чтобы проверить сглаживание следа.
    let autopilotWobble = ProcessInfo.processInfo.arguments.contains("-wobble")
    /// `-drift` — раз за круг демо-палец уводит машину на 16 м в сторону, на траву (проверка выездов).
    let autopilotDrift = ProcessInfo.processInfo.arguments.contains("-drift")
    let autopilotDirection: Float = ProcessInfo.processInfo.arguments.contains("-reverse") ? -1 : 1

    // Камера: фиксированный изометрический ракурс, следует за машиной.
    let cameraFov: Float = 32
    let cameraElevation: Float = 52 * .pi / 180
    /// Сколько метров земли видно по короткой стороне экрана.
    let visibleWidth: Float = 110
    /// Курс камеры (вперёд = (sin, cos)) и курс, к которому она сейчас доворачивается.
    var cameraYaw: Float = 0
    var cameraGoalYaw: Float = 0
    /// Камера доворачивается, только если трасса впереди ушла от текущего вида больше чем на этот угол.
    let cameraYawThreshold: Float = 18 * .pi / 180
    var cameraDistance: Float = 100
    var cameraTarget: SIMD3<Float> = .zero

    init(definition: TrackDefinition, mode: GameMode, state: GameState) {
        self.state = state
        self.mode = mode
        track = Track(definition)
        session = mode == .race ? RaceSession(track: track) : nil
        let start = GameController.spawnPose(track, session: session)
        follower = CarFollower(position: start.position, heading: start.heading, model: carModel)
        lapTimer = LapTimer(pointCount: track.points.count, startProgress: track.nearestIndex(start.position))
        // В гонке круг не аннулируется выездами — засчитывается, если пройдены все отсечки.
        lapTimer.invalidatesOnOffTrack = mode != .race && GameController.invalidatesOnOffTrack
        lastOnTrackDistance = track.nearestIndexDistance(start.position)
        if ProcessInfo.processInfo.arguments.contains("-resetRecords") { LapRecords.reset(definition.id) }
        if mode == .training {
            ghost = Ghost.load(for: definition.id)
            bestSplits = LapRecords.bestSplits(definition.id)
        }
        state.carPosition = start.position
        state.mode = mode
        state.lapsTotal = session?.lapsTotal ?? 0

        var markerMat = UnlitMaterial(color: .white)
        markerMat.blending = .transparent(opacity: 0.55)
        let markerSize = definition.carScale / 1.5
        fingerMarker = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 1.3 * markerSize), materials: [markerMat])
        super.init()
        prepareStart()
    }

    /// Гонка — последнее место на стартовой решётке. Тренировка с разгоном — за `runUpDistance` до линии
    /// (на коротких трассах ближе), без разгона — сразу за линией.
    static func spawnPose(_ track: Track, session: RaceSession?) -> (position: SIMD2<Float>, heading: Float) {
        if let session {
            let grid = session.gridPose(slot: RaceSession.playerGridSlot)
            return (grid.position, grid.heading)
        }
        guard RaceSettings.rollingStart else { return track.startPose }
        let f = track.frame(atDistance: -runUpDistance(track))
        return (f.position, atan2(f.tangent.x, f.tangent.y))
    }

    /// На коротких трассах разгон короче — машина не должна стоять дальше середины круга от линии.
    static func runUpDistance(_ track: Track) -> Float { min(runUpDistance, track.length * 0.5) }

    func prepareStart() {
        playerIndex = track.nearestIndex(follower.position)
        playerProgress = wrappedDistance(Float(playerIndex) * track.step)
        raceLaps = 0
        racePenalty = 0
        raceFinished = false
        cooldown = nil
        if isRace {
            runUp = nil
            raceLightsTime = 0
            state.startLights = .red(3)
            return
        }
        guard RaceSettings.rollingStart else { runUp = nil; return }
        runUp = RunUp(fingerDistance: -GameController.runUpDistance(track), fingerSpeed: 0)
        state.startLights = .red(3)
    }

    func makeView() -> ARView {
        let view = SceneSetup.makeView()
        arView = view

        let anchor = AnchorEntity(world: .zero)
        view.scene.addAnchor(anchor)
        self.anchor = anchor
        anchor.addChild(track.makeEntity())
        anchor.addChild(sun)

        let carScale = track.definition.carScale
        Task { @MainActor [weak self] in
            do {
                let car = try await CarEntity.load(scale: carScale, primary: self?.livery.primary,
                                                   secondary: self?.livery.secondary,
                                                   accent: self?.livery.accent,
                                                   model: self?.carModel ?? .standard)
                guard let self else { return }
                self.car = car
                anchor.addChild(car.root)
                car.update(position: self.follower.position, heading: self.follower.heading,
                           speed: 0, steer: 0, braking: false, dt: 0)
                await self.session?.loadCars(into: anchor)
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
        let start = GameController.spawnPose(track, session: session)
        follower = CarFollower(position: start.position, heading: start.heading, model: carModel)
        finger = nil
        lapTimer = LapTimer(pointCount: track.points.count, startProgress: track.nearestIndex(start.position))
        lapTimer.invalidatesOnOffTrack = mode != .race && GameController.invalidatesOnOffTrack
        session?.reset()
        lastOnTrackDistance = track.nearestIndexDistance(start.position)
        offTrackStreak = 0
        resetting = false
        touchSuspended = false
        fadeView.layer.removeAllAnimations()
        fadeView.alpha = 0
        recording = Ghost()
        ghostCar?.root.isEnabled = false
        medalGhostCar?.root.isEnabled = false
        deltaTimer = 0
        bannerTimer = 0
        autopilotDistance = -14
        car?.update(position: follower.position, heading: follower.heading, speed: 0, steer: 0, braking: false, dt: 0)
        state.reset()
        state.medalTarget = medalTarget.flatMap { m in medalRun.map { (m, $0.time) } }
        state.mode = mode
        state.lapsTotal = session?.lapsTotal ?? 0
        wrongWayTimer = 0
        state.carPosition = follower.position
        state.isLoading = car == nil
        lightsTimer = 0
        prepareStart()
        snapCamera()
    }

    /// Кадр: палец (настоящий или виртуальный) → физика машины → соперники → камера → круги → HUD.
    func update(dt: Float) {
        guard dt > 0 else { return }
        if showFPS { countFrame() }
        if arView.bounds.size != fittedSize, arView.bounds.width > 0 {
            configureCamera(for: arView.bounds.size)
        }

        if isRace { updateRaceLights(dt: dt) }
        driveVirtualFinger(dt: dt)
        let surface = checkSurface(dt: dt)
        stepPlayer(dt: dt, surface: surface)

        updateCamera(dt: dt)
        updateMarkers()
        // Пока идёт возврат на трассу, выезд не копится в «срезку» — за него будет штраф.
        updateLaps(dt: dt, offTrack: surface.offTrack && !resetting)
        updateGhost(dt: dt)

        publishState(dt: dt, offTrack: surface.offTrack)
        updateHUDTimers(dt: dt)
        updateIdleHint(dt: dt)
    }

    /// Кто ведёт машину, пока не игрок: автопилот после финиша, разгон под огни или демо-палец.
    private func driveVirtualFinger(dt: Float) {
        if cooldown != nil {
            driveCooldown(dt: dt)
        } else if runUp != nil {
            driveRunUp(dt: dt)
        } else if autopilot && !raceWaiting && !raceFinished {
            driveAutopilot(dt: dt)
        }
    }

    /// Где колёса: на асфальте, поребрике или траве. Долгий выезд — возврат на трассу (если включён).
    private func checkSurface(dt: Float) -> (offTrack: Bool, onCurb: Bool) {
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
        return (offTrack, onCurb)
    }

    /// Физика машины игрока, соперники и столкновения, модель машины, эффекты.
    private func stepPlayer(dt: Float, surface: (offTrack: Bool, onCurb: Bool)) {
        let oldSpeed = follower.speed
        follower.step(dt: dt, finger: finger, offTrack: surface.offTrack)
        updatePlayerProgress()
        if let session, car != nil {
            session.update(dt: dt, player: &follower, playerProgress: playerProgress, playerIndex: playerIndex)
            hitCooldown -= dt
            if session.playerHit && hitCooldown <= 0 {
                hitCooldown = 0.4
                haptics.collision()
            }
        }
        car?.updateWind(draft: follower.draft, dt: dt)
        car?.update(position: follower.position, heading: follower.heading, speed: follower.speed,
                    steer: follower.steer, braking: follower.braking, dt: dt)
        updateEffects(oldSpeed: oldSpeed, offTrack: surface.offTrack, onCurb: surface.onCurb, dt: dt)
        updateWrongWay(dt: dt)
    }

    /// Остановить звук при уходе с экрана гонки.
    func shutdown() {
        audio.stop()
        updateSubscription?.cancel()
    }
}
