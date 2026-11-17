import RealityKit
import os
import UIKit
import simd

/// Режим заезда.
enum GameMode: Equatable {
    case training
    case race
}

/// Скорость, которую трасса позволяет в каждой точке осевой: предел сцепления в повороте
/// и торможение заранее перед ним. По этому профилю едут соперники.
struct SpeedProfile {
    let speeds: [Float]
    private let step: Float

    /// Общий профиль соперников и медальных заездов: 92% сцепления, тормоза — 70% от предельных.
    static func standard(for track: Track) -> SpeedProfile {
        let reference = CarFollower(position: .zero, heading: 0)
        return SpeedProfile(track: track, grip: reference.grip * 0.92, brake: reference.brakeDecel * 0.7,
                            maxSpeed: reference.maxSpeed)
    }

    init(track: Track, grip: Float, brake: Float, maxSpeed: Float) {
        step = track.step
        let n = track.points.count
        let t = track.tangents
        var v = (0..<n).map { i -> Float in
            let a = t[(i - 3 + n) % n], b = t[(i + 3) % n]
            let curvature = abs(atan2(a.x * b.y - a.y * b.x, simd_dot(a, b))) / (6 * track.step)
            return curvature > 1e-5 ? min(maxSpeed, (grip / curvature).squareRoot()) : maxSpeed
        }
        // Торможение: проход назад по кругу (дважды — чтобы замкнуть круг через линию старта).
        for _ in 0..<2 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                let next = v[(i + 1) % n]
                v[i] = min(v[i], (next * next + 2 * brake * track.step).squareRoot())
            }
        }
        speeds = v
    }

    func speed(at index: Int) -> Float { speeds[index] }

    /// Скорость на дистанции `s` от линии старта (любой знак, берётся по модулю круга).
    func speed(atDistance s: Float) -> Float {
        let n = speeds.count
        return speeds[((Int((s / step).rounded()) % n) + n) % n]
    }
}

/// «Палец» автопилота: едет по трассе впереди машины со скоростью из профиля × мастерство
/// и не убегает от машины далеко. Им ездят соперники, медальные заезды и машина игрока после финиша.
struct VirtualFinger {
    /// Дистанция пальца от линии старта и его скорость.
    var distance: Float
    var speed: Float

    mutating func step(dt: Float, carProgress: Float, carSpeed: Float, target: Float) {
        distance = max(distance, carProgress + 6)
        speed = min(speed + 16 * dt, target)
        if distance - carProgress > 10 + carSpeed * 0.5 { speed = min(speed, carSpeed) }
        distance += speed * dt
    }
}

/// Соперник: та же физика, что у игрока; его «палец» едет по трассе впереди машины со скоростью
/// из профиля, умноженной на мастерство.
struct Opponent {
    let name: String
    let color: UIColor
    /// Доля от предельной скорости в поворотах (0.8…0.95).
    let skill: Float
    var follower: CarFollower
    var car: CarEntity?
    /// Пройденная дистанция гонки от линии старта (на стартовой решётке — отрицательная).
    var progress: Float
    var trackIndex: Int
    /// Смещение от осевой: базовое (своя полоса), желаемое (для обгона) и текущее.
    let baseLane: Float
    var lane: Float
    var laneNow: Float
    var virtualFinger: VirtualFinger
    var finger: SIMD2<Float>?
    /// Задержка реакции на зелёный.
    var reaction: Float
    var throttle: Float = 0
    var finishTime: Double?
    /// Прозрачность модели: падает, пока игрок проезжает сквозь машину.
    var opacity: Float = 1
}

/// Строка итоговой таблицы.
struct RaceResult: Identifiable, Equatable {
    let id: Int
    let position: Int
    let name: String
    let color: UIColor
    let isPlayer: Bool
    /// Время финиша (у тех, кто ещё не доехал, — оценка по средней скорости).
    let time: Double
}

/// Гонка против соперников: старт с места, круги, позиции, столкновения, финиш.
@MainActor
final class RaceSession {
    let track: Track
    let lapsTotal: Int
    private let profile: SpeedProfile
    private(set) var opponents: [Opponent] = []
    /// Время гонки с зелёного сигнала.
    private(set) var raceTime: Double = 0
    private(set) var started = false

    /// Сколько машин на старте и где стоит игрок (последним — есть кого обгонять).
    nonisolated static let carCount = 4
    nonisolated static var playerGridSlot: Int { carCount - 1 }

    private static let roster: [(name: String, color: UIColor, skill: Float)] = [
        ("Синий", UIColor(red: 0.15, green: 0.35, blue: 0.95, alpha: 1), 0.83),
        ("Зелёный", UIColor(red: 0.1, green: 0.7, blue: 0.3, alpha: 1), 0.78),
        ("Жёлтый", UIColor(red: 1, green: 0.75, blue: 0.1, alpha: 1), 0.73),
    ]

    private let collisions = RaceSettings.collisions
    private var playerDraft: Float = 0
    /// Ближайшая к игроку точка осевой (её считает GameController).
    private var playerIndex = 0

    /// Радиус кругов, которыми машина представлена при столкновениях (два круга — нос и корма).
    private let hitRadius: Float
    private let hitOffset: Float

    init(track: Track) {
        self.track = track
        // Для отладки: `-laps N` — короткая гонка.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-laps"), i + 1 < args.count, let laps = Int(args[i + 1]), laps > 0 {
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
            guard let car = try? await CarEntity.load(scale: track.definition.carScale, livery: opponents[i].color)
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
                RaceSession.log.info("\(o.name, privacy: .public) lap \(Int(o.progress / self.track.length)) at \(self.raceTime)")
            }
            if o.finishTime == nil && o.progress >= Float(lapsTotal) * track.length {
                o.finishTime = raceTime
            }
            opponents[i] = o
            updateVisuals(i, dt: dt)
        }
    }

    /// Разница расстояний по кругу, приведённая к (−L/2, L/2].
    private func wrapped(_ d: Float) -> Float {
        var d = d.truncatingRemainder(dividingBy: track.length)
        if d > track.length / 2 { d -= track.length }
        if d < -track.length / 2 { d += track.length }
        return d
    }

    private func lateral(of p: SIMD2<Float>, index: Int) -> Float {
        simd_dot(p - track.points[index], track.normals[index])
    }

    private func drive(_ o: inout Opponent, dt: Float, player: CarFollower, playerProgress: Float) {
        // До зелёного все стоят.
        guard started else {
            o.follower.step(dt: dt, finger: nil, offTrack: false)
            return
        }
        if o.reaction > 0 {
            o.reaction -= dt
            o.follower.step(dt: dt, finger: nil, offTrack: false)
            return
        }

        // Обгон: если впереди близко машина в той же полосе и мы быстрее — уходим в сторону, где свободнее.
        var blocker: (gap: Float, lateral: Float, speed: Float)?
        let myLateral = lateral(of: o.follower.position, index: o.trackIndex)
        func consider(progress: Float, position: SIMD2<Float>, index: Int, speed: Float) {
            let gap = progress - o.progress
            guard gap > 0, gap < 35 else { return }
            let lat = lateral(of: position, index: index)
            guard abs(lat - myLateral) < 4.5 else { return }
            if blocker == nil || gap < blocker!.gap { blocker = (gap, lat, speed) }
        }
        consider(progress: playerProgress, position: player.position, index: playerIndex, speed: player.speed)
        for other in opponents where other.name != o.name {
            consider(progress: other.progress, position: other.follower.position, index: other.trackIndex,
                     speed: other.follower.speed)
        }
        let maxLane = track.halfWidth - 2
        if let b = blocker, o.follower.speed > b.speed * 0.97 {
            let left = b.lateral - 5, right = b.lateral + 5
            o.lane = abs(left) <= maxLane && (abs(right) > maxLane || abs(left - myLateral) < abs(right - myLateral))
                ? max(left, -maxLane) : min(right, maxLane)
        } else {
            o.lane += (o.baseLane - o.lane) * min(dt * 0.3, 1)
        }
        o.laneNow += simd_clamp(o.lane - o.laneNow, -3 * dt, 3 * dt)

        // Виртуальный палец: впереди машины, со скоростью из профиля. Далеко не убегает.
        if o.finger == nil {
            o.virtualFinger = VirtualFinger(distance: o.progress + 8, speed: max(o.follower.speed, 5))
        }
        o.virtualFinger.step(dt: dt, carProgress: o.progress, carSpeed: o.follower.speed,
                             target: profile.speed(atDistance: o.virtualFinger.distance) * o.skill)
        let f = track.frame(atDistance: o.virtualFinger.distance)
        let point = f.position + SIMD2(f.tangent.y, -f.tangent.x) * o.laneNow
        if o.finger == nil { o.follower.touchBegan(at: point) }
        o.finger = point

        let oldSpeed = o.follower.speed
        o.follower.step(dt: dt, finger: point, offTrack: false)
        let accel = (o.follower.speed - oldSpeed) / dt
        o.throttle += (simd_clamp(accel / 12, 0, 1) - o.throttle) * (1 - exp(-dt / 0.15))
    }

    /// Столкновения: машины — по два круга (нос и корма). Пересекшиеся круги расталкиваются,
    /// машина сзади теряет скорость до скорости передней.
    private(set) var playerHit = false

    private func resolveCollisions(player: inout CarFollower, playerProgress: Float) {
        playerHit = false
        var cars: [(follower: CarFollower, progress: Float)] = opponents.map { ($0.follower, $0.progress) }
        cars.append((player, playerProgress))
        let minDistance = 2 * hitRadius
        for a in 0..<cars.count {
            for b in (a + 1)..<cars.count {
                let fa = SIMD2(sin(cars[a].follower.heading), cos(cars[a].follower.heading))
                let fb = SIMD2(sin(cars[b].follower.heading), cos(cars[b].follower.heading))
                for oa in [-hitOffset, hitOffset] {
                    for ob in [-hitOffset, hitOffset] {
                        let pa = cars[a].follower.position + fa * oa
                        let pb = cars[b].follower.position + fb * ob
                        let d = pb - pa
                        let dist = simd_length(d)
                        guard dist < minDistance, dist > 1e-3 else { continue }
                        let push = d / dist * (minDistance - dist) / 2
                        let aBehind = cars[a].progress < cars[b].progress
                        let front = aBehind ? cars[b].follower.speed : cars[a].follower.speed
                        // Задняя машина упирается в переднюю и теряет скорость, передняя почти не замечает удара.
                        cars[a].follower.bump(by: -push, limit: aBehind ? front * 0.97 : cars[a].follower.speed)
                        cars[b].follower.bump(by: push, limit: aBehind ? cars[b].follower.speed : front * 0.97)
                        if b == cars.count - 1 { playerHit = true }
                    }
                }
            }
        }
        for i in opponents.indices { opponents[i].follower = cars[i].follower }
        player = cars[cars.count - 1].follower
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

    private static let log = Logger(subsystem: "com.example.RaceGame", category: "race")

    /// Касаются ли машины (те же круги, что для столкновений, с небольшим запасом).
    private func overlaps(_ a: CarFollower, _ b: CarFollower) -> Bool {
        guard simd_distance(a.position, b.position) < 2 * (hitOffset + hitRadius) + 1 else { return false }
        let fa = SIMD2(sin(a.heading), cos(a.heading)), fb = SIMD2(sin(b.heading), cos(b.heading))
        for oa in [-hitOffset, hitOffset] {
            for ob in [-hitOffset, hitOffset] where simd_distance(a.position + fa * oa, b.position + fb * ob) < 2 * hitRadius + 0.5 {
                return true
            }
        }
        return false
    }

    /// Слипстрим игрока: машина впереди в 8–40 м и почти в той же полосе. Ближе — сильнее.
    /// Только на высокой скорости (с 180 км/ч, в полную силу — с 210 км/ч) и при ровной езде:
    /// в заносе или в резком повороте поток срывается.
    private func draft(for player: CarFollower, playerProgress: Float) -> Float {
        let speedFactor = simd_clamp((player.speed - 180 / 3.6) / (30 / 3.6), 0, 1)
        let smooth = player.slide < 0.05 && player.lateralAccel < 0.5 * player.grip
        guard started, speedFactor > 0, smooth else { return 0 }
        let lat = lateral(of: player.position, index: playerIndex)
        var best: Float = 0
        for o in opponents {
            let gap = o.progress - playerProgress
            guard gap > 8, gap < 40, abs(lateral(of: o.follower.position, index: o.trackIndex) - lat) < 3.5 else { continue }
            best = max(best, 1 - (gap - 8) / 32)
        }
        return best * speedFactor
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
