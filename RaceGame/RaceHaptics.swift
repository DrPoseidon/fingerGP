import UIKit

/// Вибрация: дробь на поребриках, шорох на траве, отклики на круг, рекорд и неверное направление.
@MainActor
final class RaceHaptics {
    private let curb = UIImpactFeedbackGenerator(style: .rigid)
    private let grass = UIImpactFeedbackGenerator(style: .soft)
    private let bump = UIImpactFeedbackGenerator(style: .heavy)
    private let tick = UIImpactFeedbackGenerator(style: .medium)
    private let notify = UINotificationFeedbackGenerator()

    private var curbDistance: Float = 0
    private var grassTimer: Float = 0
    private var wasOnGrass = false
    private var wasOnCurb = false
    private var curbCooldown: Float = 0

    init() {
        curb.prepare()
        grass.prepare()
        tick.prepare()
    }

    /// Вызывается раз в кадр.
    func update(speed: Float, onCurb: Bool, onGrass: Bool, dt: Float) {
        // Поребрик: толчок сразу при наезде, дальше на каждой второй полосе (≈ раз в 3.6 м),
        // не чаще ~14 раз в секунду. Раньше первый толчок ждал 3.6 м — короткие касания не чувствовались.
        curbCooldown -= dt
        if onCurb && speed > 3 {
            curbDistance += speed * dt
            let step = max(3.6, speed / 14)
            if (!wasOnCurb || curbDistance >= step) && curbCooldown <= 0 {
                curbDistance = 0
                curbCooldown = 1.0 / 14
                curb.impactOccurred(intensity: CGFloat(min(0.45 + speed / 120, 0.9)))
            }
        } else {
            curbDistance = 0
        }
        wasOnCurb = onCurb && speed > 3

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

    /// Отсечка сектора: одиночный короткий толчок.
    func sector() {
        tick.impactOccurred(intensity: 0.7)
    }

    /// Стартовые огни: лёгкий толчок на каждом погасшем красном, сильный — на зелёный.
    func countdown(go: Bool) {
        if go { bump.impactOccurred(intensity: 1) } else { tick.impactOccurred(intensity: 0.6) }
    }

    func wrongWay() {
        notify.notificationOccurred(.warning)
    }
}
