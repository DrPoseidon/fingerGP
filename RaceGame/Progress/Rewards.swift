import Foundation
import Observation
import UIKit

/// Сколько монет за что.
@MainActor
enum Rewards {
    private static let defaults = UserDefaults.standard

    /// Тренировка: за улучшение своего рекорда.
    static let record = 25

    /// Новая медаль на трассе: за каждую ступень — один раз (сразу на золото — за все три).
    static func medal(_ medal: Medal?, on id: TrackID) -> Int {
        guard let medal else { return 0 }
        let key = "reward.medal.\(id.rawValue)"
        let rewarded = defaults.integer(forKey: key)
        guard medal.rawValue > rewarded else { return 0 }
        defaults.set(medal.rawValue, forKey: key)
        let prices = [Medal.bronze: 50, .silver: 100, .gold: 200]
        return Medal.allCases.filter { $0.rawValue > rewarded && $0 <= medal }.reduce(0) { $0 + prices[$1]! }
    }

    /// Гонка: за место, с поправкой на длину гонки; первая победа на трассе — бонус.
    static func race(place: Int, on id: TrackID) -> Int {
        let base = [150, 100, 60, 30][min(max(place, 1), 4) - 1]
        let factor: Double
        switch id {
        case .oval: factor = 0.8
        case .harbor: factor = 1
        case .pass: factor = 1.2
        case .forest: factor = 1.5
        }
        var total = Int((Double(base) * factor).rounded())
        let winKey = "reward.firstWin.\(id.rawValue)"
        if place == 1 && !defaults.bool(forKey: winKey) {
            defaults.set(true, forKey: winKey)
            total += 100
        }
        return total
    }
}
