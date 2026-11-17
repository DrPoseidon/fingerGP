import SwiftUI

/// Сообщение по центру экрана гонки: «Не то направление», «Новый рекорд!», «Круг не засчитан».
struct HUDBanner: View {
    enum Style {
        /// Красный — предупреждение.
        case warning
        /// Золотой — успех.
        case success
        /// Тёмный — нейтральное.
        case neutral
    }

    let icon: String
    let text: String
    var style: Style = .neutral

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .heavy))
            Text(text.uppercased())
                .font(.system(size: 20, weight: .black, design: .rounded))
        }
        .foregroundStyle(style == .success ? .black : .white)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(background, in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }

    private var background: Color {
        switch style {
        case .warning: return Theme.brandRed.opacity(0.92)
        case .success: return Theme.gold
        case .neutral: return Color(white: 0.2).opacity(0.9)
        }
    }
}
