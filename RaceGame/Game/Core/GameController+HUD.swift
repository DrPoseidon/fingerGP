import SwiftUI
import RealityKit
import Combine
import os

/// Передача состояния в HUD (SwiftUI): мини-карта 30 раз в секунду, цифры — 10 раз,
/// временные сообщения исчезают по таймерам, подсказка жестом — при простое.
extension GameController {
    func publishState(dt: Float, offTrack: Bool) {
        minimapTimer += dt
        if minimapTimer >= 1.0 / 30 {
            minimapTimer = 0
            state.carPosition = follower.position
            state.cameraYaw = cameraYaw
            state.ghostPosition = ghostCar.flatMap(groundPosition)
            state.medalGhostPosition = medalGhostCar.flatMap(groundPosition)
            if let session {
                state.opponents = session.minimapCars.map { MinimapCar(position: $0.position, color: $0.color) }
            }
        }

        hudTimer += dt
        if hudTimer >= 0.1 {
            hudTimer = 0
            state.speedKmh = Int((follower.speed * 3.6).rounded())
            state.currentLapTime = lapTimer.lapTime
            state.offTrack = offTrack && follower.speed > 0.5
            if let session, !raceFinished {
                state.raceTime = session.raceTime + racePenalty
                state.racePosition = session.playerPosition(playerProgress: playerProgress, playerFinish: nil)
                state.raceLap = min(raceLaps + 1, session.lapsTotal)
                let wasDrafting = state.draft > 0.3
                state.draft = follower.draft
                if !wasDrafting && follower.draft > 0.3 { haptics.sector() }
            }
        }
    }

    /// Положение призрака на земле, если он сейчас виден.
    private func groundPosition(_ ghost: GhostCar) -> SIMD2<Float>? {
        ghost.root.isEnabled ? SIMD2(ghost.root.position.x, ghost.root.position.z) : nil
    }

    /// Временные сообщения: разница по сектору, баннер, монеты, стартовые огни.
    func updateHUDTimers(dt: Float) {
        expire(&deltaTimer, dt: dt) { state.delta = nil }
        expire(&bannerTimer, dt: dt) { state.banner = nil }
        expire(&coinTimer, dt: dt) { state.coinToast = nil }
        expire(&lightsTimer, dt: dt) { state.startLights = nil }
    }

    /// Таймер, по истечении которого сообщение убирается (0 — не активен).
    private func expire(_ timer: inout Float, dt: Float, onExpire: () -> Void) {
        guard timer > 0 else { return }
        timer -= dt
        if timer <= 0 { onExpire() }
    }

    /// Машина стоит без пальца дольше `idleHintDelay` — показать анимацию «веди пальцем».
    func updateIdleHint(dt: Float) {
        let idle = finger == nil && follower.speed < 0.5 && runUp == nil && !resetting && !state.isLoading
            && !raceWaiting && !raceFinished
        idleTime = idle ? idleTime + dt : 0
        let showHint = idleTime > idleHintDelay
        if showHint && !state.showGestureHint { state.gestureHintPath = gestureHintPath() }
        if state.showGestureHint != showHint { state.showGestureHint = showHint }
    }
}
