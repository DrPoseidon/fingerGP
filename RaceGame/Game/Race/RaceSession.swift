import RealityKit
import os
import UIKit
import simd

/// Гонка против соперников: старт с места, круги, позиции, столкновения, финиш.
@MainActor
final class RaceSession {
    let track: Track
    let lapsTotal: Int
    let profile: SpeedProfile
    var opponents: [Opponent] = []
    /// Время гонки с зелёного сигнала.
    private(set) var raceTime: Double = 0
    private(set) var started = false

    /// Сколько машин на старте и где стоит игрок (последним — есть кого обгонять).
    nonisolated static let carCount = 6
    nonisolated static var playerGridSlot: Int { carCount - 1 }

    private static let roster: [(name: String, color: UIColor, skill: Float)] = [
        ("Синий", UIColor(red: 0.15, green: 0.35, blue: 0.95, alpha: 1), 0.9),
        ("Фиолетовый", UIColor(red: 0.6, green: 0.25, blue: 0.9, alpha: 1), 0.88),
        ("Зелёный", UIColor(red: 0.1, green: 0.7, blue: 0.3, alpha: 1), 0.86),
        ("Голубой", UIColor(red: 0.2, green: 0.8, blue: 0.9, alpha: 1), 0.84),
        ("Жёлтый", UIColor(red: 1, green: 0.75, blue: 0.1, alpha: 1), 0.82),
    ]

    let collisions = RaceSettings.collisions
    var playerDraft: Float = 0
    /// Ближайшая к игроку точка осевой (её считает GameController).
    var playerIndex = 0
    /// Столкновения: машины — по два круга (нос и корма). Пересекшиеся круги расталкиваются,
    /// машина сзади теряет скорость до скорости передней.
    var playerHit = false

    /// Радиус кругов, которыми машина представлена при столкновениях (два круга — нос и корма).
    let hitRadius: Float
    let hitOffset: Float

    init(track: Track) {
        self.track = track
        // Для отладки: `-laps N` — короткая гонка.
        if let laps = DebugFlags.int("-laps"), laps > 0 {
            lapsTotal = laps
        } else {
            switch track.definition.id {
            case .oval: lapsTotal = 5
            case .forest: lapsTotal = 2
            default: lapsTotal = 3
            }
        }
        profile = SpeedProfile.standard(for: track)
        hitRadius = 1.1 * track.definition.carScale
        hitOffset = 0.9 * track.definition.carScale
        reset()
    }

    /// Место на стартовой решётке: по два в ряд, ряды через 9 м, первый — в 8 м за линией.
    func gridPose(slot: Int) -> (position: SIMD2<Float>, heading: Float, distance: Float) {
        let distance = -(8 + 9 * Float(slot)) * track.definition.carScale / 2
        let f = track.frame(atDistance: distance)
        let normal = SIMD2(f.tangent.y, -f.tangent.x)
        let side: Float = slot % 2 == 0 ? -3.5 : 3.5
        return (f.position + normal * side, atan2(f.tangent.x, f.tangent.y), distance)
    }

    func reset() {
        raceTime = 0
        playerDraft = 0
        started = false
        let cars = opponents.map(\.car)
        opponents = RaceSession.roster.enumerated().map { i, r in
            let grid = gridPose(slot: i)
            let lane: Float = i % 2 == 0 ? -3.5 : 3.5
            return Opponent(name: r.name, color: r.color, skill: r.skill,
                            follower: CarFollower(position: grid.position, heading: grid.heading),
                            car: i < cars.count ? cars[i] : nil,
                            progress: grid.distance, trackIndex: track.nearestIndex(grid.position),
                            baseLane: lane, lane: lane, laneNow: lane,
                            virtualFinger: VirtualFinger(distance: grid.distance, speed: 0), reaction: Float.random(in: 0.1...0.4))
        }
        for o in opponents {
            o.car?.update(position: o.follower.position, heading: o.follower.heading,
                          speed: 0, steer: 0, braking: false, dt: 0)
        }
    }

    /// Загрузить машины соперников (каждая в своей ливрее) и добавить в сцену.
    func loadCars(into anchor: Entity) async {
        for i in opponents.indices where opponents[i].car == nil {
            guard let car = try? await CarEntity.load(scale: track.definition.carScale, primary: opponents[i].color,
                                                       detail: .reduced)
            else { continue }
            opponents[i].car = car
            anchor.addChild(car.root)
            car.update(position: opponents[i].follower.position, heading: opponents[i].follower.heading,
                       speed: 0, steer: 0, braking: false, dt: 0)
        }
    }

    func start() { started = true }

    /// Шаг соперников. `player` — машина игрока: с ней тоже сталкиваются и её объезжают.
    func update(dt: Float, player: inout CarFollower, playerProgress: Float, playerIndex: Int) {
        self.playerIndex = playerIndex
        if started { raceTime += Double(dt) }
        for i in opponents.indices {
            var o = opponents[i]
            drive(&o, dt: dt, player: player, playerProgress: playerProgress)
            opponents[i] = o
        }
        // Плавно: слипстрим нарастает и пропадает за ~0.3 с, без мигания на границах.
        let target = draft(for: player, playerProgress: playerProgress)
        playerDraft += simd_clamp(target - playerDraft, -3 * dt, 3 * dt)
        player.draft = playerDraft
        if collisions { resolveCollisions(player: &player, playerProgress: playerProgress) }
        for i in opponents.indices {
            let touching = overlaps(opponents[i].follower, player)
            let target: Float = touching ? 0.35 : 1
            opponents[i].opacity += simd_clamp(target - opponents[i].opacity, -4 * dt, 4 * dt)
        }
        for i in opponents.indices {
            var o = opponents[i]
            let index = track.nearestIndex(o.follower.position, near: o.trackIndex)
            let before = o.progress
            o.progress += wrapped(Float(index - o.trackIndex) * track.step)
            o.trackIndex = index
            if floor(before / track.length) < floor(o.progress / track.length) && o.progress > 1 {
                Log.race.info("\(o.name, privacy: .public) lap \(Int(o.progress / self.track.length)) at \(self.raceTime)")
            }
            if o.finishTime == nil && o.progress >= Float(lapsTotal) * track.length {
                o.finishTime = raceTime
            }
            opponents[i] = o
            updateVisuals(i, dt: dt)
        }
    }

    /// Разница расстояний по кругу, приведённая к (−L/2, L/2].
    func wrapped(_ d: Float) -> Float {
        var d = d.truncatingRemainder(dividingBy: track.length)
        if d > track.length / 2 { d -= track.length }
        if d < -track.length / 2 { d += track.length }
        return d
    }

    func lateral(of p: SIMD2<Float>, index: Int) -> Float {
        simd_dot(p - track.points[index], track.normals[index])
    }

    private func updateVisuals(_ i: Int, dt: Float) {
        let o = opponents[i]
        guard let car = o.car else { return }
        car.update(position: o.follower.position, heading: o.follower.heading, speed: o.follower.speed,
                   steer: o.follower.steer, braking: o.follower.braking, dt: dt)
        var smoke: Float = 0
        if o.follower.speed > 12 {
            smoke = simd_clamp(max((o.follower.lateralAccel / o.follower.grip - 0.75) / 0.25, o.follower.slide * 2), 0, 1)
        }
        car.updateEffects(speed: o.follower.speed, throttle: o.throttle, smoke: smoke)
        car.setOpacity(o.opacity)
    }


    /// Позиция игрока (1 — лидер): кто финишировал раньше — выше, остальные — по пройденной дистанции.
    func playerPosition(playerProgress: Float, playerFinish: Double?) -> Int {
        1 + opponents.filter { o in
            if let t = o.finishTime { return playerFinish.map { t < $0 } ?? true }
            return playerFinish == nil && o.progress > playerProgress
        }.count
    }

    /// Итоговая таблица в момент финиша игрока. У недоехавших соперников время — оценка
    /// по оставшейся дистанции и их средней скорости.
    func results(playerTime: Double) -> [RaceResult] {
        let total = Float(lapsTotal) * track.length
        var rows: [(name: String, color: UIColor, player: Bool, time: Double)] = opponents.map { o in
            if let t = o.finishTime { return (o.name, o.color, false, t) }
            let covered = max(o.progress, 1)
            let average = Double(covered) / max(raceTime, 1)
            return (o.name, o.color, false, raceTime + Double(total - o.progress) / max(average, 1))
        }
        rows.append(("Вы", UIColor(red: 0.86, green: 0.13, blue: 0.13, alpha: 1), true, playerTime))
        rows.sort { $0.time < $1.time }
        return rows.enumerated().map { i, r in
            RaceResult(id: i, position: i + 1, name: r.name, color: r.color, isPlayer: r.player, time: r.time)
        }
    }

    /// Скорость из профиля трассы на дистанции `s` от старта — для автопилота игрока после финиша.
    func profileSpeed(atDistance s: Float) -> Float { profile.speed(atDistance: s) }

    /// Положения и цвета соперников для мини-карты.
    var minimapCars: [(position: SIMD2<Float>, color: UIColor)] {
        opponents.map { ($0.follower.position, $0.color) }
    }
}
