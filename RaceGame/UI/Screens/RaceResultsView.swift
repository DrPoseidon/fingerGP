import SwiftUI

/// Итоги гонки: места, время победителя и отставания остальных.
struct RaceResultsView: View {
    let results: [RaceResult]
    let bestLap: Double?
    let reward: Int
    let onRestart: () -> Void
    let onExit: () -> Void

    var body: some View {
        let place = results.first(where: \.isPlayer)?.position ?? results.count
        let leader = results.first?.time ?? 0
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Image(systemName: place == 1 ? "trophy.fill" : "flag.checkered")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(place == 1 ? Theme.gold : .white)
                    Text(place == 1 ? "Победа!" : "Финиш · \(place)-е место")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                }
                VStack(spacing: 8) {
                    ForEach(results) { r in
                        HStack(spacing: 12) {
                            Text("\(r.position)")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .frame(width: 22)
                            Circle().fill(Color(r.color)).frame(width: 14, height: 14)
                            Text(r.name)
                                .font(.system(size: 17, weight: r.isPlayer ? .heavy : .semibold))
                            Spacer()
                            Text(r.position == 1 ? formatLapTime(r.time) : "+" + String(format: "%.2f", r.time - leader))
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(r.isPlayer ? Color.white.opacity(0.18) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if let bestLap {
                    Text("Лучший круг: \(formatLapTime(bestLap))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .opacity(0.8)
                }
                if reward > 0 {
                    CoinBalance(coins: reward, plus: true)
                }
                HStack(spacing: 12) {
                    CapsuleButton(title: "В меню", style: .ghost, action: onExit)
                    CapsuleButton(title: "Ещё раз", style: .filled(Theme.brandRed), action: onRestart)
                }
            }
            .foregroundStyle(.white)
            .padding(22)
            .background(Color(white: 0.1).opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 20)
        }
    }
}
