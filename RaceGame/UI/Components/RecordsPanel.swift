import SwiftUI

/// Статистика в меню: лучший круг и число кругов по каждой трассе.
struct RecordsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Лучшие круги")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .opacity(0.85)
            ForEach(TrackDefinition.all, id: \.id) { def in
                HStack(spacing: 10) {
                    TrackOutline(points: TrackPreview.get(def.id).points)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 30, height: 22)
                    Text(def.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer()
                    let laps = LapRecords.lapCount(def.id)
                    if laps > 0 {
                        Text("\(laps) кр.")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0.6)
                    }
                    if let place = LapRecords.racePlace(def.id) {
                        RaceTrophy(place: place)
                    }
                    MedalIcon(medal: MedalStore.shared.earned(on: def.id), size: 16)
                    Text(LapRecords.bestLap(def.id).map(formatLapTime) ?? "—:——.——")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .opacity(LapRecords.bestLap(def.id) == nil ? 0.45 : 1)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: 340)
        .glassPanel()
    }
}
