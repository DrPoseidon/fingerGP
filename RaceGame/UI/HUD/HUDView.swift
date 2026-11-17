import SwiftUI

struct HUDView: View {
    let state: GameState
    let trackName: String

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                HUDInfoPanel(state: state, trackName: trackName)
                Spacer()
            }
            if let fps = state.fps {
                FPSBadge(average: fps.average, worstMs: fps.worstMs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.wrongWay {
                HUDBanner(icon: "arrow.uturn.backward", text: "Не то направление", style: .warning)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if let banner = state.banner {
                HUDBanner(icon: state.bannerIcon, text: banner, style: state.bannerIsGood ? .success : .neutral)
                    .padding(.top, 12)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if let coins = state.coinToast {
                CoinBalance(coins: coins, plus: true)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // Подсказка — в верхней части экрана: внизу стоит машина (камера смотрит вперёд) и мини-карта.
            if state.showHint && !state.hasTouched && (state.startLights == nil || state.startLights == .green) {
                Text("Веди пальцем по трассе — машина поедет следом.\nБыстрее палец — быстрее машина.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 24)
            }
            Spacer()
        }
        .padding()
        .overlay {
            ZStack {
                if let lights = state.startLights {
                    StartLightsView(lights: lights)
                        .transition(.opacity)
                }
            }
            .offset(y: -60)
            .animation(.easeOut(duration: 0.3), value: state.startLights)
            .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.25), value: state.wrongWay)
        .animation(.easeOut(duration: 0.25), value: state.banner)
        .animation(.spring(duration: 0.35), value: state.coinToast)
    }
}
