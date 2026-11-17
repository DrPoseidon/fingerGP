import SwiftUI

struct MenuView: View {
    let onPlay: () -> Void
    let onGarage: () -> Void
    @State private var muted = RaceAudio.isMuted
    /// `-screen settings` — открыть меню сразу с настройками (для скриншотов).
    @State private var showSettings = DebugFlags.value("-screen") == "settings"

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 90)
            VStack(spacing: 6) {
                Text("FINGER GP")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .italic()
                Text("Веди пальцем — машина поедет следом")
                    .font(.system(size: 15, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
            Spacer()
            RecordsPanel()
                .padding(.bottom, 28)
            CapsuleButton(title: "Играть", style: .hero(Theme.brandRed), maxWidth: 280, action: onPlay)
            CapsuleButton(title: "Гараж", icon: "car.fill", style: .subtle, maxWidth: 280, action: onGarage)
                .padding(.top, 12)
            Spacer().frame(height: 60)
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .topLeading) {
            CoinBalance(coins: Wallet.shared.coins)
                .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                CircleButton(systemName: "gearshape.fill") { showSettings = true }
                CircleButton(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    muted.toggle()
                    RaceAudio.isMuted = muted
                }
            }
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}
