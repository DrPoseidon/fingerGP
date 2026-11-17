import SwiftUI
import RealityKit
import Combine
import os

/// Возврат на трассу после выезда.
extension GameController {
    /// Возврат на трассу: сцена затемняется, машина ставится на осевую линию там, где съехала,
    /// стоя на месте и по направлению трассы; к кругу добавляется штраф.
    func beginResetToTrack() {
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

    func respawnOnTrack() {
        let frame = track.frame(atDistance: lastOnTrackDistance)
        let heading = atan2(frame.tangent.x, frame.tangent.y)
        follower = CarFollower(position: frame.position, heading: heading, model: carModel)
        car?.update(position: frame.position, heading: heading, speed: 0, steer: 0, braking: false, dt: 0)
        updatePlayerProgress()
        offTrackStreak = 0
        lapTimer.forgiveCurrentExcursion()
        // «Не засчитывать круг» — выезд с возвратом аннулирует круг; «Игнорировать» — только штраф по времени.
        let invalidates = lapTimer.invalidatesOnOffTrack && lapTimer.isRunning
        if invalidates {
            lapTimer.invalidate()
        } else {
            lapTimer.addPenalty(RaceSettings.resetPenalty)
            if isRace { racePenalty += RaceSettings.resetPenalty }
        }
        Log.laps.info("respawn at distance=\(self.lastOnTrackDistance) lapTime=\(self.lapTimer.lapTime)")
        showBanner(invalidates ? "Возврат на трассу · круг не засчитан"
                   : String(format: "Возврат на трассу · +%.0f с", RaceSettings.resetPenalty), good: false,
                   icon: "arrow.uturn.backward.circle.fill")
        snapCamera()
    }
}
