import UIKit

/// Вибрация: дробь на поребриках, шорох на траве, отклики на круг, рекорд и неверное направление.
@MainActor
final class RaceHaptics {
    private let curb = UIImpactFeedbackGenerator(style: .rigid)
    private let grass = UIImpactFeedbackGenerator(style: .soft)
    private let bump = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    private var curbDistance: Float = 0
    private var grassTimer: Float = 0
    private var wasOnGrass = false

    init() {
        curb.prepare()
        grass.prepare()
    }

    /// Вызывается раз в кадр.
    func update(speed: Float, onCurb: Bool, onGrass: Bool, dt: Float) {
        // Поребрик: толчок на каждой второй полосе (≈ раз в 3.6 м), не чаще ~14 раз в секунду.
        if onCurb && speed > 3 {
            curbDistance += speed * dt
            let step = max(3.6, speed / 14)
            if curbDistance >= step {
                curbDistance = 0
                curb.impactOccurred(intensity: CGFloat(min(0.35 + speed / 120, 0.8)))
            }
        } else {
            curbDistance = 0
        }

        // Трава: удар при вылете и неровная мелкая тряска, пока едешь по ней.
        if onGrass && !wasOnGrass && speed > 15 {
            bump.impactOccurred(intensity: CGFloat(min(speed / 60, 1)))
        }
        wasOnGrass = onGrass
        if onGrass && speed > 2 {
            grassTimer -= dt
            if grassTimer <= 0 {
                grassTimer = Float.random(in: 0.07...0.14)
                grass.impactOccurred(intensity: CGFloat(min(0.25 + speed / 80, 0.7)))
            }
        }
    }

    func lap(record: Bool) {
        notify.notificationOccurred(.success)
        if record { bump.impactOccurred(intensity: 1) }
    }

    func wrongWay() {
        notify.notificationOccurred(.warning)
    }
}
