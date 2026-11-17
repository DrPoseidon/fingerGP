import SwiftUI
import RealityKit
import Combine
import os

/// Старт с хода (разгон под огни) и демо-автопилот.
extension GameController {
    /// Разгон к линии старта: виртуальный палец едет по осевой впереди машины с крейсерской скоростью,
    /// медленнее — если впереди поворот. Разгон начинается, когда машина загружена.
    func driveRunUp(dt: Float) {
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
    func safeSpeed(atDistance s: Float) -> Float {
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
    func driveAutopilot(dt: Float) {
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
}
