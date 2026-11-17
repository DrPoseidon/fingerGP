import SwiftUI
import RealityKit
import Combine

/// Монета: жёлтый кружок с ободком.
struct CoinIcon: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 1, green: 0.78, blue: 0.15))
            Circle().stroke(Color(red: 0.85, green: 0.55, blue: 0.05), lineWidth: size * 0.12)
                .padding(size * 0.14)
            Text("F")
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.75, green: 0.45, blue: 0.02))
        }
        .frame(width: size, height: size)
    }
}

/// Баланс или награда: «🪙 1 250» / «+ 🪙 25».
struct CoinBalance: View {
    let coins: Int
    var plus = false

    var body: some View {
        HStack(spacing: 6) {
            if plus { Text("+").font(.system(size: 18, weight: .black, design: .rounded)) }
            CoinIcon(size: 20)
            Text("\(coins)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
    }
}
