import Foundation

/// Статистика по трассам, сохраняется между запусками (UserDefaults): лучший круг и число пройденных кругов.
enum LapRecords {
    private static let defaults = UserDefaults.standard

    static func bestLap(_ id: TrackID) -> Double? {
        let value = defaults.double(forKey: "bestLap.\(id.rawValue)")
        return value > 0 ? value : nil
    }

    static func lapCount(_ id: TrackID) -> Int {
        defaults.integer(forKey: "laps.\(id.rawValue)")
    }

    /// Засчитать пройденный круг. Возвращает true, если это новый рекорд трассы.
    @discardableResult
    static func recordLap(_ id: TrackID, time: Double) -> Bool {
        defaults.set(lapCount(id) + 1, forKey: "laps.\(id.rawValue)")
        guard time < bestLap(id) ?? .infinity else { return false }
        defaults.set(time, forKey: "bestLap.\(id.rawValue)")
        return true
    }
}

/// Время круга в виде «1:23.45».
func formatLapTime(_ t: Double) -> String {
    String(format: "%d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
}
