import simd

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
