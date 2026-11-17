import Foundation
import simd

/// Статистика по трассам, сохраняется между запусками: лучший круг, его сектора, число кругов (UserDefaults)
/// и запись лучшего круга для призрака (файл в Application Support).
enum LapRecords {
    private static let defaults = UserDefaults.standard

    static func bestLap(_ id: TrackID) -> Double? {
        let value = defaults.double(forKey: "bestLap.\(id.rawValue)")
        return value > 0 ? value : nil
    }

    /// Время лучшего круга на границах секторов (накопленное с начала круга).
    static func bestSplits(_ id: TrackID) -> [Double]? {
        defaults.array(forKey: "splits.\(id.rawValue)") as? [Double]
    }

    static func lapCount(_ id: TrackID) -> Int {
        defaults.integer(forKey: "laps.\(id.rawValue)")
    }

    /// Разовая миграция: рекорды, поставленные до честного зачёта и призрака, не имеют записи призрака
    /// и могли быть со срезкой. Их сбрасываем (число кругов остаётся) — первый честный круг станет рекордом.
    static func dropLegacyRecords() {
        let flag = "migration.legacyRecordsDropped.v1"
        guard !defaults.bool(forKey: flag) else { return }
        for id in TrackID.allCases where bestLap(id) != nil && !Ghost.exists(for: id) {
            defaults.removeObject(forKey: "bestLap.\(id.rawValue)")
            defaults.removeObject(forKey: "splits.\(id.rawValue)")
        }
        defaults.set(true, forKey: flag)
    }

    /// Разовая миграция: Монцу, Спа и Нордшляйфе заменили свои трассы — их статистику и призраков удаляем.
    static func dropRemovedTracks() {
        let flag = "migration.removedTracksDropped.v1"
        guard !defaults.bool(forKey: flag) else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ghosts", isDirectory: true)
        for id in ["monza", "spa", "nordschleife"] {
            for key in ["bestLap", "splits", "laps"] { defaults.removeObject(forKey: "\(key).\(id)") }
            if let file = dir?.appendingPathComponent("\(id).bin") { try? FileManager.default.removeItem(at: file) }
        }
        defaults.set(true, forKey: flag)
    }

    /// Сбросить статистику трассы (для отладки: аргумент запуска `-resetRecords`).
    static func reset(_ id: TrackID) {
        for key in ["bestLap", "splits", "laps", "racePlace", "challengeBest"] { defaults.removeObject(forKey: "\(key).\(id.rawValue)") }
        Ghost.delete(for: id)
    }

    /// Лучший круг в «Испытании» — по нему выдаются медали.
    static func challengeBest(_ id: TrackID) -> Double? {
        let value = defaults.double(forKey: "challengeBest.\(id.rawValue)")
        return value > 0 ? value : nil
    }

    /// Засчитать круг «Испытания». Возвращает true, если это новый лучший.
    @discardableResult
    static func recordChallengeLap(_ id: TrackID, time: Double) -> Bool {
        guard time < challengeBest(id) ?? .infinity else { return false }
        defaults.set(time, forKey: "challengeBest.\(id.rawValue)")
        return true
    }

    /// Разовая миграция: медали раньше считались по рекорду тренировки — переносим его в «Испытание»,
    /// чтобы уже полученные медали не пропали.
    static func seedChallengeRecords() {
        let flag = "migration.challengeSeeded.v1"
        guard !defaults.bool(forKey: flag) else { return }
        for id in TrackID.allCases {
            if let best = bestLap(id), challengeBest(id) == nil { defaults.set(best, forKey: "challengeBest.\(id.rawValue)") }
        }
        defaults.set(true, forKey: flag)
    }

    /// Лучшее место в гонке на трассе (1 — победа), nil — гонок не было.
    static func racePlace(_ id: TrackID) -> Int? {
        let value = defaults.integer(forKey: "racePlace.\(id.rawValue)")
        return value > 0 ? value : nil
    }

    static func recordRacePlace(_ id: TrackID, place: Int) {
        guard place < racePlace(id) ?? .max else { return }
        defaults.set(place, forKey: "racePlace.\(id.rawValue)")
    }

    /// Засчитать честный круг. Возвращает true, если это новый рекорд трассы.
    @discardableResult
    static func recordLap(_ id: TrackID, time: Double, splits: [Double], ghost: Ghost) -> Bool {
        defaults.set(lapCount(id) + 1, forKey: "laps.\(id.rawValue)")
        guard time < bestLap(id) ?? .infinity else { return false }
        defaults.set(time, forKey: "bestLap.\(id.rawValue)")
        defaults.set(splits, forKey: "splits.\(id.rawValue)")
        ghost.save(for: id)
        return true
    }
}
