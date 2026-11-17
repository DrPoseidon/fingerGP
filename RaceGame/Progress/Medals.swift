import Foundation
import Observation
import UIKit
import simd

/// Медали тренировки: бронза, серебро и золото за время круга.
enum Medal: Int, CaseIterable, Comparable, Identifiable {
    case bronze = 1, silver, gold

    var id: Int { rawValue }
    static func < (a: Medal, b: Medal) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .bronze: return "Бронза"
        case .silver: return "Серебро"
        case .gold: return "Золото"
        }
    }

    var color: UIColor {
        switch self {
        case .bronze: return UIColor(red: 0.85, green: 0.52, blue: 0.27, alpha: 1)
        case .silver: return UIColor(red: 0.8, green: 0.84, blue: 0.9, alpha: 1)
        case .gold: return UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        }
    }

    /// Мастерство автопилота, который ставит медальное время (доля от скорости профиля трассы).
    var skill: Float {
        switch self {
        case .bronze: return 0.72
        case .silver: return 0.79
        case .gold: return 0.86
        }
    }
}

/// Медальный круг: время, время на отсечках секторов и запись для призрака-цели.
struct MedalRun: Codable {
    let time: Double
    let splits: [Double]
    let ghost: Ghost
}

/// Медальные круги считаются при запуске, в фоне: автопилот с мастерством медали проезжает быстрый
/// круг с той же физикой, что у игрока. Так медальное время всегда достижимо и сходится с призраком.
@MainActor
@Observable
final class MedalStore {
    static let shared = MedalStore()

    private(set) var runs: [TrackID: [Medal: MedalRun]] = [:]
    /// Меняется после каждого рекорда — чтобы экраны перечитали медали.
    private(set) var revision = 0

    /// Сколько медальных очков (бронза 1, серебро 2, золото 3) нужно, чтобы открыть трассу.
    static func requiredPoints(_ id: TrackID) -> Int {
        switch id {
        case .oval, .harbor: return 0
        case .pass: return 2
        case .forest: return 5
        }
    }

    /// Для отладки: `-unlockAll` открывает все трассы.
    private let unlockAll = DebugFlags.has("-unlockAll")

    /// Медальные круги берутся из кэша; считаются заново, только если кэша нет или он от другой версии
    /// (новая сборка или изменилась физика — тогда поднять `cacheVersion`). Считать их — сотни миллисекунд
    /// работы процессора на трассу, при каждом запуске это тормозило старт.
    func prepare() {
        guard runs.isEmpty else { return }
        Task.detached(priority: .utility) {
            if let cached = MedalStore.loadCache() {
                await MainActor.run { MedalStore.shared.runs = cached }
                return
            }
            var all: [TrackID: [Medal: MedalRun]] = [:]
            for definition in TrackDefinition.all {
                let track = Track(definition)
                let profile = SpeedProfile.standard(for: track)
                var result: [Medal: MedalRun] = [:]
                for medal in Medal.allCases {
                    if let run = MedalStore.simulate(track, profile: profile, skill: medal.skill) { result[medal] = run }
                }
                all[definition.id] = result
                await MainActor.run { MedalStore.shared.runs[definition.id] = result }
            }
            MedalStore.saveCache(all)
        }
    }

    // MARK: - Кэш медальных кругов

    /// Поднять при изменении физики машины, профиля скорости или трасс.
    private nonisolated static let cacheVersion = 1

    private nonisolated static var cacheURL: URL? {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("medals-v\(cacheVersion)-\(build).json")
    }

    private nonisolated static func loadCache() -> [TrackID: [Medal: MedalRun]]? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [Int: MedalRun]].self, from: data) else { return nil }
        var result: [TrackID: [Medal: MedalRun]] = [:]
        for (key, runs) in raw {
            guard let id = TrackID(rawValue: key) else { continue }
            result[id] = Dictionary(uniqueKeysWithValues: runs.compactMap { k, v in Medal(rawValue: k).map { ($0, v) } })
        }
        // Кэш неполный (например, добавили трассу) — считать заново.
        guard TrackID.allCases.allSatisfy({ result[$0]?.count == Medal.allCases.count }) else { return nil }
        return result
    }

    private nonisolated static func saveCache(_ runs: [TrackID: [Medal: MedalRun]]) {
        guard let url = cacheURL else { return }
        let raw = Dictionary(uniqueKeysWithValues: runs.map { id, medals in
            (id.rawValue, Dictionary(uniqueKeysWithValues: medals.map { ($0.key.rawValue, $0.value) }))
        })
        try? JSONEncoder().encode(raw).write(to: url, options: .atomic)
    }

    func recordsChanged() { revision += 1 }

    func time(_ medal: Medal, on id: TrackID) -> Double? { runs[id]?[medal]?.time }

    /// Лучшая медаль за время круга `lap`.
    func medal(for lap: Double?, on id: TrackID) -> Medal? {
        guard let lap else { return nil }
        return Medal.allCases.reversed().first { m in time(m, on: id).map { lap <= $0 } ?? false }
    }

    /// Медаль по лучшему кругу «Испытания».
    func earned(on id: TrackID) -> Medal? {
        _ = revision
        return medal(for: LapRecords.challengeBest(id), on: id)
    }

    /// Следующая цель: медаль на ступень выше заработанной (nil — золото уже есть или времена не готовы).
    func nextTarget(on id: TrackID) -> Medal? {
        let current = earned(on: id)?.rawValue ?? 0
        return Medal(rawValue: current + 1)
    }

    var points: Int { TrackID.allCases.reduce(0) { $0 + (earned(on: $1)?.rawValue ?? 0) } }

    func isUnlocked(_ id: TrackID) -> Bool { unlockAll || points >= MedalStore.requiredPoints(id) }

    // MARK: - Медальный заезд

    /// Быстрый круг автопилота: разгон с 300 м до линии, круг от линии до линии с записью для призрака.
    nonisolated static func simulate(_ track: Track, profile: SpeedProfile, skill: Float) -> MedalRun? {
        let runUp = min(300, track.length * 0.5)
        let start = track.frame(atDistance: -runUp)
        var car = CarFollower(position: start.position, heading: atan2(start.tangent.x, start.tangent.y))
        var progress = -runUp
        var index = track.nearestIndex(car.position)
        car.launch(speed: min(30, profile.speed(atDistance: progress) * skill))
        var finger = VirtualFinger(distance: progress + 8, speed: car.speed)
        car.touchBegan(at: track.frame(atDistance: finger.distance).position)

        let dt: Float = 1.0 / 60
        var lapTime: Double?
        var samples: [SIMD4<Float>] = []
        var splits: [Double] = []
        // Отсечки — там же, где у LapTimer: на n·k/3 точках осевой.
        let n = track.points.count
        let boundaries = (1..<LapTimer.sectorCount).map { Float(n * $0 / LapTimer.sectorCount) * track.step }
        for _ in 0..<(60 * 600) {
            finger.step(dt: dt, carProgress: progress, carSpeed: car.speed,
                        target: profile.speed(atDistance: finger.distance) * skill)
            car.step(dt: dt, finger: track.frame(atDistance: finger.distance).position, offTrack: false)

            let i = track.nearestIndex(car.position, near: index)
            var delta = Float(i - index) * track.step
            if delta > track.length / 2 { delta -= track.length }
            if delta < -track.length / 2 { delta += track.length }
            let before = progress
            progress += delta
            index = i

            if lapTime == nil, before < 0, progress >= 0 { lapTime = 0 }
            guard var t = lapTime else { continue }
            t += Double(dt)
            lapTime = t
            while Double(samples.count) * Ghost.interval <= t {
                samples.append(SIMD4(car.position.x, car.position.y, car.heading, car.speed))
            }
            if splits.count < boundaries.count, progress >= boundaries[splits.count] { splits.append(t) }
            if progress >= track.length { return MedalRun(time: t, splits: splits, ghost: Ghost(samples: samples)) }
        }
        return nil
    }
}
