import SwiftUI
import RealityKit
import Combine

/// Полоска характеристики: 1.0 — стандартная машина (середина шкалы).
struct StatBar: View {
    let title: String
    let value: Float

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(width: 70, alignment: .leading).opacity(0.8)
            GeometryReader { geo in
                let fraction = CGFloat(min(max((value - 0.85) / 0.3, 0.05), 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(value > 1.001 ? Theme.faster
                                   : value < 0.999 ? Theme.worse : .white.opacity(0.8))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(width: 110, height: 6)
        }
    }
}
