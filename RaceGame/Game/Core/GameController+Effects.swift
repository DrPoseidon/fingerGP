import SwiftUI
import RealityKit
import Combine
import os

/// Эффекты, звук, вибрация, «не то направление», маркеры пальца, подсказка жестом, счётчик FPS.
extension GameController {
    /// Жест подсказки: касание на трассе чуть впереди машины и проведение по ней вперёд, повторяя повороты.
    func gestureHintPath() -> [CGPoint] {
        let s = track.nearestIndexDistance(follower.position)
        return stride(from: Float(18), through: 115, by: 4).compactMap { d in
            let p = track.frame(atDistance: s + d).position
            return arView.project(SIMD3(p.x, 0, p.y))
        }
    }

    /// Выхлоп гуще при разгоне; дым из-под колёс — в резком повороте (близко к пределу сцепления) и при сносе.
    func updateEffects(oldSpeed: Float, offTrack: Bool, onCurb: Bool, dt: Float) {
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

    /// «Не то направление»: машина едет против хода трассы дольше секунды.
    func updateWrongWay(dt: Float) {
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

    func updateMarkers() {
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

    func countFrame() {
        let now = CACurrentMediaTime()
        if fpsLastFrame > 0 { fpsWorst = max(fpsWorst, now - fpsLastFrame) }
        fpsLastFrame = now
        fpsFrames += 1
        if fpsWindowStart == 0 { fpsWindowStart = now }
        if now - fpsWindowStart >= 0.5 {
            state.fps = (Double(fpsFrames) / (now - fpsWindowStart), fpsWorst * 1000)
            fpsFrames = 0
            fpsWindowStart = now
            fpsWorst = 0
        }
    }
}
