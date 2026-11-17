import RealityKit
import os
import UIKit
import simd

/// Как едут соперники: виртуальный палец по профилю скорости и обгон медленных по соседней полосе.
extension RaceSession {
    func drive(_ o: inout Opponent, dt: Float, player: CarFollower, playerProgress: Float) {
        // До зелёного все стоят.
        guard started else {
            o.follower.step(dt: dt, finger: nil, offTrack: false)
            return
        }
        if o.reaction > 0 {
            o.reaction -= dt
            o.follower.step(dt: dt, finger: nil, offTrack: false)
            return
        }

        // Обгон: если впереди близко машина в той же полосе и мы быстрее — уходим в сторону, где свободнее.
        var blocker: (gap: Float, lateral: Float, speed: Float)?
        let myLateral = lateral(of: o.follower.position, index: o.trackIndex)
        func consider(progress: Float, position: SIMD2<Float>, index: Int, speed: Float) {
            let gap = progress - o.progress
            guard gap > 0, gap < 35 else { return }
            let lat = lateral(of: position, index: index)
            guard abs(lat - myLateral) < 4.5 else { return }
            if blocker == nil || gap < blocker!.gap { blocker = (gap, lat, speed) }
        }
        consider(progress: playerProgress, position: player.position, index: playerIndex, speed: player.speed)
        for other in opponents where other.name != o.name {
            consider(progress: other.progress, position: other.follower.position, index: other.trackIndex,
                     speed: other.follower.speed)
        }
        let maxLane = track.halfWidth - 2
        if let b = blocker, o.follower.speed > b.speed * 0.97 {
            let left = b.lateral - 5, right = b.lateral + 5
            o.lane = abs(left) <= maxLane && (abs(right) > maxLane || abs(left - myLateral) < abs(right - myLateral))
                ? max(left, -maxLane) : min(right, maxLane)
        } else {
            o.lane += (o.baseLane - o.lane) * min(dt * 0.3, 1)
        }
        o.laneNow += simd_clamp(o.lane - o.laneNow, -3 * dt, 3 * dt)

        // Виртуальный палец: впереди машины, со скоростью из профиля. Далеко не убегает.
        if o.finger == nil {
            o.virtualFinger = VirtualFinger(distance: o.progress + 8, speed: max(o.follower.speed, 5))
        }
        o.virtualFinger.step(dt: dt, carProgress: o.progress, carSpeed: o.follower.speed,
                             target: profile.speed(atDistance: o.virtualFinger.distance) * o.skill)
        let f = track.frame(atDistance: o.virtualFinger.distance)
        let point = f.position + SIMD2(f.tangent.y, -f.tangent.x) * o.laneNow
        if o.finger == nil { o.follower.touchBegan(at: point) }
        o.finger = point

        let oldSpeed = o.follower.speed
        o.follower.step(dt: dt, finger: point, offTrack: false)
        let accel = (o.follower.speed - oldSpeed) / dt
        o.throttle += (simd_clamp(accel / 12, 0, 1) - o.throttle) * (1 - exp(-dt / 0.15))
    }
}
