import Foundation

/// Что делать, когда машина выехала за трассу.
enum OffTrackRule: String, CaseIterable, Identifiable {
    /// Долгий выезд (срезка) — круг не засчитывается.
    case invalidate
    /// Выезды не влияют на зачёт круга.
    case ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invalidate: return "Не засчитывать круг"
        case .ignore: return "Игнорировать"
        }
    }
}

/// Настройки гонки, сохраняются между запусками.
enum RaceSettings {
    static let offTrackRuleKey = "settings.offTrackRule"
    static let resetToTrackKey = "settings.resetToTrack"

    /// Через сколько секунд за поребриком машина возвращается на трассу (раньше, чем круг аннулируется).
    static let resetDelay: Double = 0.5
    /// Штраф за возврат на трассу, секунды.
    static let resetPenalty: Double = 2

    static var offTrackRule: OffTrackRule {
        OffTrackRule(rawValue: UserDefaults.standard.string(forKey: offTrackRuleKey) ?? "") ?? .invalidate
    }

    static var resetToTrack: Bool {
        UserDefaults.standard.bool(forKey: resetToTrackKey)
    }
}
