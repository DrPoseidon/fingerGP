import SwiftUI

/// Как режим выглядит в меню: значок, название, описание, цвет.
extension GameMode: CaseIterable, Identifiable {
    static let allCases: [GameMode] = [.training, .challenge, .race]
    var id: Self { self }

    var title: String {
        switch self {
        case .training: return "Тренировка"
        case .challenge: return "Испытание"
        case .race: return "Гонка"
        }
    }

    var subtitle: String {
        switch self {
        case .training: return "Свободные круги: свой призрак и своё время — улучшай рекорд"
        case .challenge: return "Бронза, серебро и золото за время круга — медали открывают трассы"
        case .race: return "Старт с последнего места против трёх соперников — обгони всех за несколько кругов"
        }
    }

    var icon: String {
        switch self {
        case .training: return "stopwatch"
        case .challenge: return "medal.fill"
        case .race: return "flag.checkered"
        }
    }

    var color: Color {
        switch self {
        case .training: return Theme.brandRed
        case .challenge: return Theme.challengeGold
        case .race: return Theme.raceBlue
        }
    }
}
