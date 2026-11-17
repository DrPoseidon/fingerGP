import SwiftUI

/// Цвета игры — в одном месте, чтобы экраны и HUD выглядели единообразно.
enum Theme {
    /// Фирменный красный: кнопка «Играть», режим «Тренировка», переключатели, тревожные баннеры.
    static let brandRed = Color(red: 0.86, green: 0.13, blue: 0.13)
    /// Режим «Гонка» и кнопки «Выбрать».
    static let raceBlue = Color(red: 0.16, green: 0.42, blue: 0.95)
    /// Режим «Испытание».
    static let challengeGold = Color(red: 0.9, green: 0.62, blue: 0.08)
    /// Золото: рекорды, победа, место в гонке, баннер успеха.
    static let gold = Color(red: 1, green: 0.8, blue: 0.2)
    /// Быстрее / медленнее лучшего круга.
    static let faster = Color(red: 0.3, green: 0.95, blue: 0.4)
    static let slower = Color(red: 1, green: 0.35, blue: 0.3)
    /// Характеристика машины хуже стандартной.
    static let worse = Color(red: 1, green: 0.55, blue: 0.3)
    /// Значок слипстрима.
    static let slipstream = Color(red: 0.45, green: 0.85, blue: 1)
    /// Фон гаража.
    static let garageBackground = Color(red: 0.08, green: 0.09, blue: 0.12)
}

extension View {
    /// «Стеклянная» панель меню: размытый фон, скругление, тёмная схема для текста.
    func glassPanel(cornerRadius: CGFloat = 18) -> some View {
        background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: cornerRadius))
            .environment(\.colorScheme, .dark)
    }
}
