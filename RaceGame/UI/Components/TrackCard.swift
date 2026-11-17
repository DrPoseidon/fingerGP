import SwiftUI

struct TrackCard: View {
    let definition: TrackDefinition
    /// Что показывать: в тренировке — свой рекорд, в испытании — медали, в гонке — лучшее место.
    let mode: GameMode
    var unlocked = true

    var body: some View {
        let preview = TrackPreview.get(definition.id)
        HStack(spacing: 16) {
            TrackOutline(points: preview.points)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 110, height: 80)
                .padding(10)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                Text(definition.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(String(format: "%.2f км", preview.length / 1000))
                    switch mode {
                    case .training:
                        if let best = LapRecords.bestLap(definition.id) {
                            Label(formatLapTime(best), systemImage: "stopwatch")
                        }
                    case .challenge:
                        if let best = LapRecords.challengeBest(definition.id) {
                            Label(formatLapTime(best), systemImage: "stopwatch")
                        }
                    case .race:
                        if let place = LapRecords.racePlace(definition.id) {
                            Label("лучшее место: \(place)", systemImage: "trophy.fill")
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .opacity(0.7)
                let store = MedalStore.shared
                if unlocked && mode == .challenge {
                    // Медальные времена: полученные — яркие, остальные — приглушённые.
                    let earned = store.earned(on: definition.id)
                    HStack(spacing: 8) {
                        ForEach(Medal.allCases) { medal in
                            if let time = store.time(medal, on: definition.id) {
                                let got = earned.map { medal <= $0 } ?? false
                                HStack(spacing: 3) {
                                    Image(systemName: "medal.fill").foregroundStyle(Color(medal.color))
                                    Text(formatLapTime(time))
                                }
                                .opacity(got ? 1 : 0.45)
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
                } else if !unlocked {
                    // Очки медалей: бронза — 1, серебро — 2, золото — 3.
                    Label("Медали: \(store.points)/\(MedalStore.requiredPoints(definition.id)) — бронза 1, серебро 2, золото 3",
                          systemImage: "medal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(Medal.gold.color))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            Image(systemName: unlocked ? "chevron.right" : "lock.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .opacity(unlocked ? 1 : 0.6)
        .glassPanel()
    }
}
