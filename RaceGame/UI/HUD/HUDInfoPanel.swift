import SwiftUI

/// Панель в левом верхнем углу: в гонке — место, скорость, круг и время гонки; в тренировке и
/// испытании — скорость, круг и время круга. Ниже — разница по сектору, лучший круг, цель, «вне трассы».
struct HUDInfoPanel: View {
    let state: GameState
    let trackName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.mode == .race {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(state.racePosition)/\(RaceSession.carCount)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    Text("\(state.speedKmh) км/ч")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                }
                Text("\(trackName) · круг \(state.raceLap)/\(state.lapsTotal)")
                    .font(.system(size: 14, weight: .semibold))
                Text(formatLapTime(state.raceTime))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                if state.draft > 0.3 {
                    Label("Слипстрим", systemImage: "wind")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.slipstream)
                }
            } else {
                Text("\(state.speedKmh) км/ч")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Text("\(trackName) · круг \(state.laps)")
                    .font(.system(size: 14, weight: .semibold))
                Text(formatLapTime(state.currentLapTime))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }
            if state.lapInvalid {
                Text("КРУГ НЕ ЗАСЧИТАН")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.orange)
            } else if let delta = state.delta {
                // Минус — быстрее лучшего круга (зелёный), плюс — медленнее (красный).
                Text("\(state.deltaLabel)  \(formatDelta(delta))")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(delta < 0 ? Theme.faster
                                     : delta > 0 ? Theme.slower : .white)
            }
            if let best = state.bestLap {
                Text("Лучший: \(formatLapTime(best))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            if let target = state.medalTarget {
                HStack(spacing: 5) {
                    MedalIcon(medal: target.medal, size: 13)
                    Text("Цель: \(formatLapTime(target.time))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }
            if state.offTrack {
                Text("ВНЕ ТРАССЫ")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.yellow)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
