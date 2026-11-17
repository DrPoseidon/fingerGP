import SwiftUI

/// Пауза: продолжить, начать заново или выйти в меню.
struct PauseView: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onResume)
            VStack(spacing: 14) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                Text("Пауза")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .padding(.bottom, 6)
                CapsuleButton(title: "Продолжить", icon: "play.fill", style: .filled(Theme.brandRed), action: onResume)
                CapsuleButton(title: "Заново", icon: "arrow.counterclockwise", style: .ghost, action: onRestart)
                CapsuleButton(title: "В меню", icon: "house.fill", style: .ghost, action: onExit)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(white: 0.1).opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
