import SwiftUI

/// Кнопка-капсула: главная (цветная, крупная) или второстепенная (полупрозрачная).
struct CapsuleButton: View {
    enum Style {
        /// Крупная цветная кнопка («Играть»).
        case hero(Color)
        /// Цветная кнопка обычного размера («Ещё раз»).
        case filled(Color)
        /// Полупрозрачная тёмная — поверх сцены («Гараж»).
        case subtle
        /// Полупрозрачная светлая — на тёмной панели («В меню»).
        case ghost
    }

    let title: String
    var icon: String?
    var style: Style = .filled(Theme.brandRed)
    /// nil — на всю доступную ширину.
    var maxWidth: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(.white)
                .frame(maxWidth: maxWidth ?? .infinity)
                .padding(.vertical, isHero ? 18 : 14)
                .background(background, in: Capsule())
                .shadow(color: .black.opacity(isHero ? 0.35 : 0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var isHero: Bool {
        if case .hero = style { return true }
        return false
    }

    private var background: Color {
        switch style {
        case .hero(let color), .filled(let color): return color
        case .subtle: return .black.opacity(0.45)
        case .ghost: return .white.opacity(0.15)
        }
    }

    @ViewBuilder private var label: some View {
        let font = Font.system(size: isHero ? 24 : 18, weight: isHero ? .heavy : .bold, design: .rounded)
        if let icon {
            Label(title, systemImage: icon).font(font)
        } else {
            Text(title).font(font)
        }
    }
}
