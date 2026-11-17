import SwiftUI

/// Значок медали: цветной кружок с медалью; nil — пустой контур (медали ещё нет).
struct MedalIcon: View {
    let medal: Medal?
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: medal == nil ? "circle.dashed" : "medal.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(medal.map { Color($0.color) } ?? .white.opacity(0.35))
    }
}

/// Лучшее место в гонке: кубок с номером места.
struct RaceTrophy: View {
    let place: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "trophy.fill")
            Text("\(place)")
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(place == 1 ? Theme.gold : .white.opacity(0.75))
    }
}
