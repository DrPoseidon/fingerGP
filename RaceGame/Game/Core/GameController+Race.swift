import SwiftUI
import RealityKit
import Combine
import os

/// Режим «Гонка»: дистанция игрока, стартовые огни, круги, финиш, автопилот после финиша.
extension GameController {
    /// Разница расстояний по кругу, приведённая к (−L/2, L/2].
    func wrappedDistance(_ d: Float) -> Float {
        var d = d.truncatingRemainder(dividingBy: track.length)
        if d > track.length / 2 { d -= track.length }
        if d < -track.length / 2 { d += track.length }
        return d
    }

    func updatePlayerProgress() {
        let index = track.nearestIndex(follower.position, near: playerIndex)
        playerProgress += wrappedDistance(Float(index - playerIndex) * track.step)
        playerIndex = index
    }

    /// Старт с места: после загрузки три красных огня гаснут по секунде, затем загорается зелёный.
    func updateRaceLights(dt: Float) {
        guard var t = raceLightsTime, !state.isLoading else { return }
        let before = t
        t += dt
        for (i, at) in [Float(1), 2, 3].enumerated() where before < at && t >= at {
            state.startLights = .red(2 - i)
            audio.play(.countdown)
            haptics.countdown(go: false)
        }
        if t >= 3.7 {
            raceLightsTime = nil
            state.startLights = .green
            audio.play(.go)
            haptics.countdown(go: true)
            lightsTimer = 1.2
            session?.start()
        } else {
            raceLightsTime = t
        }
    }

    func finishRaceLap(time: Double, valid: Bool) {
        guard let session, !raceFinished else { return }
        guard valid else {
            showBanner("Срезка · круг не засчитан", good: false)
            return
        }
        raceLaps += 1
        state.laps = raceLaps
        state.bestLap = min(state.bestLap ?? .infinity, time)
        if raceLaps >= session.lapsTotal {
            finishRace()
        } else {
            audio.play(.lap)
            haptics.lap(record: false)
            if raceLaps == session.lapsTotal - 1 { showBanner("Последний круг", good: true, icon: "flag.checkered") }
        }
    }

    func finishRace() {
        guard let session else { return }
        raceFinished = true
        // Палец отпускается, дальше машину спокойно ведёт автопилот.
        finger = nil
        cooldown = VirtualFinger(distance: playerProgress + 8, speed: follower.speed)
        follower.touchBegan(at: track.frame(atDistance: playerProgress + 8).position)
        let total = session.raceTime + racePenalty
        let results = session.results(playerTime: total)
        let place = results.first(where: \.isPlayer)?.position ?? session.lapsTotal
        state.raceTime = total
        state.racePosition = place
        state.raceResults = results
        LapRecords.recordRacePlace(track.definition.id, place: place)
        let coins = Rewards.race(place: place, on: track.definition.id)
        Wallet.shared.earn(coins)
        state.raceReward = coins
        MedalStore.shared.recordsChanged()
        audio.play(place == 1 ? .record : .lap)
        haptics.lap(record: place == 1)
    }

    /// Автопилот после финиша: как соперники — палец впереди машины со скоростью ~70% от предельной.
    func driveCooldown(dt: Float) {
        guard var c = cooldown, let session else { return }
        c.step(dt: dt, carProgress: playerProgress, carSpeed: follower.speed,
               target: session.profileSpeed(atDistance: c.distance) * 0.7)
        finger = track.frame(atDistance: c.distance).position
        cooldown = c
    }
}
