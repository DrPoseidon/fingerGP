import SwiftUI

/// Стартовые огни: три красных гаснут по очереди, потом все три загораются зелёным.
struct StartLightsView: View {
    let lights: StartLights

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { i in
                let color: Color? = switch lights {
                case .green: Color(red: 0.2, green: 1, blue: 0.35)
                case .red(let lit): i < lit ? Color(red: 1, green: 0.12, blue: 0.1) : nil
                }
                Circle()
                    .fill(color ?? Color(white: 0.18))
                    .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 3))
                    .frame(width: 52, height: 52)
                    .shadow(color: color?.opacity(0.9) ?? .clear, radius: 14)
                    .animation(.easeOut(duration: 0.12), value: lights)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color(white: 0.08).opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }
}
