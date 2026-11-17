import SwiftUI
import RealityKit
import Combine
import os

/// Круги: зачёт, сектора, рекорды, медали «Испытания», призраки, сообщения в HUD.
extension GameController {
    /// Зачёт круга, сектора и запись круга для призрака.
    func updateLaps(dt: Float, offTrack: Bool) {
        let events = lapTimer.update(progress: track.nearestIndex(follower.position), offTrack: offTrack, dt: Double(dt))
        if lapTimer.isRunning && mode == .training {
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
                if isRace {
                    finishRaceLap(time: time, valid: valid)
                } else if valid && mode == .challenge {
                    finishChallengeLap(time: time)
                } else if valid {
                    finishLap(time: time, splits: splits)
                } else {
                    showBanner("Круг не засчитан", good: false)
                }
            }
        }
    }

    static let lapLog = Logger(subsystem: "com.example.RaceGame", category: "laps")

    func finishLap(time: Double, splits: [Double]) {
        let id = track.definition.id
        let previousBest = LapRecords.bestLap(id)
        state.laps += 1
        state.bestLap = min(state.bestLap ?? .infinity, time)
        if let previousBest { showDelta(time - previousBest, label: "Круг") }

        let isRecord = LapRecords.recordLap(id, time: time, splits: splits, ghost: recording)
        if isRecord {
            ghost = recording
            bestSplits = splits
            MedalStore.shared.recordsChanged()
        }
        // Первый круг на трассе — просто круг; рекорд — когда побит прежний. Монеты — за улучшение рекорда.
        let celebrate = isRecord && previousBest != nil
        if celebrate {
            showBanner("Новый рекорд!", good: true)
            Wallet.shared.earn(Rewards.record)
            showCoins(Rewards.record)
        }
        audio.play(celebrate ? .record : .lap)
        haptics.lap(record: celebrate)
    }

    /// Круг «Испытания»: сравнение с временем медали-цели, медали и монеты за них.
    func finishChallengeLap(time: Double) {
        let id = track.definition.id
        let store = MedalStore.shared
        state.laps += 1
        state.bestLap = min(state.bestLap ?? .infinity, time)
        if let target = medalRun { showDelta(time - target.time, label: "Цель") }

        let oldMedal = store.earned(on: id)
        let isBest = LapRecords.recordChallengeLap(id, time: time)
        if isBest { store.recordsChanged() }
        let newMedal = store.earned(on: id)
        if let newMedal, oldMedal.map({ newMedal > $0 }) ?? true {
            showBanner("\(newMedal.title)!", good: true, icon: "medal.fill")
            let coins = Rewards.medal(newMedal, on: id)
            Wallet.shared.earn(coins)
            showCoins(coins)
            updateMedalTarget()
            audio.play(.record)
            haptics.lap(record: true)
        } else {
            audio.play(.lap)
            haptics.lap(record: false)
        }
    }

    /// Цель — следующая медаль; медальные круги считаются в фоне, поэтому могут появиться не сразу.
    func updateMedalTarget() {
        guard mode == .challenge else { return }
        let store = MedalStore.shared
        let target = store.nextTarget(on: track.definition.id)
        let run = target.flatMap { store.runs[track.definition.id]?[$0] }
        guard target != medalTarget || (run != nil) != (medalRun != nil) else { return }
        medalTarget = target
        medalRun = run
        // Время по секторам — против медального круга.
        bestSplits = run?.splits
        state.medalTarget = target.flatMap { m in run.map { (m, $0.time) } }
        medalGhostCar?.root.removeFromParent()
        medalGhostCar = nil
        if let target, run != nil, let anchor {
            let ghost = GhostCar(scale: track.definition.carScale, color: target.color)
            ghost.root.isEnabled = false
            anchor.addChild(ghost.root)
            medalGhostCar = ghost
        }
    }

    /// Призраки повторяют лучший круг и медальный круг синхронно с текущим: в одно и то же время от старта круга.
    func updateGhost(dt: Float) {
        if medalRun == nil && medalTarget == nil || medalGhostCar == nil { updateMedalTarget() }
        if let medalGhostCar {
            if lapTimer.isRunning, let pose = medalRun?.ghost.pose(at: lapTimer.lapTime) {
                medalGhostCar.root.isEnabled = true
                medalGhostCar.update(position: pose.position, heading: pose.heading)
            } else {
                medalGhostCar.root.isEnabled = false
            }
        }
        guard let ghostCar else { return }
        guard lapTimer.isRunning, let pose = ghost?.pose(at: lapTimer.lapTime) else {
            ghostCar.root.isEnabled = false
            return
        }
        ghostCar.root.isEnabled = true
        ghostCar.update(position: pose.position, heading: pose.heading)
    }

    func showCoins(_ amount: Int) {
        guard amount > 0 else { return }
        state.coinToast = amount
        coinTimer = 2.5
    }

    func showDelta(_ delta: Double, label: String) {
        state.delta = delta
        state.deltaLabel = label
        deltaTimer = 3
    }

    func showBanner(_ text: String, good: Bool, icon: String? = nil) {
        state.banner = text
        state.bannerIsGood = good
        state.bannerIcon = icon ?? (good ? "trophy.fill" : "xmark.octagon.fill")
        bannerTimer = 2.5
    }
}
