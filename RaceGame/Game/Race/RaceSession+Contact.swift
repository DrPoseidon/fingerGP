import RealityKit
import os
import UIKit
import simd

/// Контакт машин: столкновения, «касание» для полупрозрачности, слипстрим игрока.
extension RaceSession {
    func resolveCollisions(player: inout CarFollower, playerProgress: Float) {
        playerHit = false
        var cars: [(follower: CarFollower, progress: Float)] = opponents.map { ($0.follower, $0.progress) }
        cars.append((player, playerProgress))
        let minDistance = 2 * hitRadius
        for a in 0..<cars.count {
            for b in (a + 1)..<cars.count {
                let fa = SIMD2(sin(cars[a].follower.heading), cos(cars[a].follower.heading))
                let fb = SIMD2(sin(cars[b].follower.heading), cos(cars[b].follower.heading))
                for oa in [-hitOffset, hitOffset] {
                    for ob in [-hitOffset, hitOffset] {
                        let pa = cars[a].follower.position + fa * oa
                        let pb = cars[b].follower.position + fb * ob
                        let d = pb - pa
                        let dist = simd_length(d)
                        guard dist < minDistance, dist > 1e-3 else { continue }
                        let push = d / dist * (minDistance - dist) / 2
                        let aBehind = cars[a].progress < cars[b].progress
                        let front = aBehind ? cars[b].follower.speed : cars[a].follower.speed
                        // Задняя машина упирается в переднюю и теряет скорость, передняя почти не замечает удара.
                        cars[a].follower.bump(by: -push, limit: aBehind ? front * 0.97 : cars[a].follower.speed)
                        cars[b].follower.bump(by: push, limit: aBehind ? cars[b].follower.speed : front * 0.97)
                        if b == cars.count - 1 { playerHit = true }
                    }
                }
            }
        }
        for i in opponents.indices { opponents[i].follower = cars[i].follower }
        player = cars[cars.count - 1].follower
    }

    /// Касаются ли машины (те же круги, что для столкновений, с небольшим запасом).
    func overlaps(_ a: CarFollower, _ b: CarFollower) -> Bool {
        guard simd_distance(a.position, b.position) < 2 * (hitOffset + hitRadius) + 1 else { return false }
        let fa = SIMD2(sin(a.heading), cos(a.heading)), fb = SIMD2(sin(b.heading), cos(b.heading))
        for oa in [-hitOffset, hitOffset] {
            for ob in [-hitOffset, hitOffset] where simd_distance(a.position + fa * oa, b.position + fb * ob) < 2 * hitRadius + 0.5 {
                return true
            }
        }
        return false
    }

    /// Слипстрим игрока: машина впереди в 8–40 м и почти в той же полосе. Ближе — сильнее.
    /// Только на высокой скорости (с 180 км/ч, в полную силу — с 210 км/ч) и при ровной езде:
    /// в заносе или в резком повороте поток срывается.
    func draft(for player: CarFollower, playerProgress: Float) -> Float {
        let speedFactor = simd_clamp((player.speed - 180 / 3.6) / (30 / 3.6), 0, 1)
        let smooth = player.slide < 0.05 && player.lateralAccel < 0.5 * player.grip
        guard started, speedFactor > 0, smooth else { return 0 }
        let lat = lateral(of: player.position, index: playerIndex)
        var best: Float = 0
        for o in opponents {
            let gap = o.progress - playerProgress
            guard gap > 8, gap < 40, abs(lateral(of: o.follower.position, index: o.trackIndex) - lat) < 3.5 else { continue }
            best = max(best, 1 - (gap - 8) / 32)
        }
        return best * speedFactor
    }
}
