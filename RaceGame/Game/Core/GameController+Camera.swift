import SwiftUI
import RealityKit
import Combine
import os

/// Камера: ракурс, поворот по трассе впереди, удержание машины и трассы в кадре.
extension GameController {
    /// Дистанция камеры подбирается так, чтобы по короткой стороне экрана было видно `visibleWidth` метров.
    func configureCamera(for size: CGSize) {
        fittedSize = size
        camera.camera.fieldOfViewInDegrees = cameraFov
        let aspect = Float(size.width / size.height)
        let tanV = tan(cameraFov * .pi / 180 / 2)
        let visibleHeight = aspect < 1 ? visibleWidth / aspect : visibleWidth
        cameraDistance = visibleHeight * sin(cameraElevation) / (2 * tanV)
        sun.shadow?.shadowProjection = .automatic(maximumDistance: cameraDistance + 120)
        snapCamera()
    }

    var cameraForward: SIMD2<Float> { SIMD2(sin(cameraYaw), cos(cameraYaw)) }

    var cameraBack: SIMD3<Float> {
        let f = cameraForward
        return SIMD3(-f.x * cos(cameraElevation), sin(cameraElevation), -f.y * cos(cameraElevation))
    }

    /// Расстояние по трассе до машины (ближайшая точка осевой).
    var carTrackDistance: Float { track.nearestIndexDistance(follower.position) }

    /// Куда в целом уходит трасса на ближайших ~150 м: средняя из хорд от машины к точкам впереди.
    /// Хорды, а не касательные, — так учитывается, куда трасса реально сместится на экране,
    /// а мелкие изгибы и шиканы почти не влияют.
    func trackAheadYaw() -> Float {
        let s = carTrackDistance
        let base = track.frame(atDistance: s).position
        var sum = SIMD2<Float>(repeating: 0)
        for d in stride(from: Float(30), through: 150, by: 30) {
            let chord = track.frame(atDistance: s + d).position - base
            sum += chord / max(simd_length(chord), 1)
        }
        return atan2(sum.x, sum.y)
    }

    /// Куда смотреть: на точку трассы впереди машины (по самой трассе, а не по прямой),
    /// так в кадре оказывается именно будущий участок, а машина — в нижней части экрана.
    func cameraGoal() -> SIMD3<Float> {
        let s = carTrackDistance
        let lead = min(60 + follower.speed * 0.3, 95)
        let lateral = follower.position - track.frame(atDistance: s).position
        let p = track.frame(atDistance: s + lead).position + lateral * 0.5
        return SIMD3(p.x, 0, p.y)
    }

    func snapCamera() {
        cameraYaw = trackAheadYaw()
        cameraGoalYaw = cameraYaw
        state.cameraYaw = cameraYaw
        cameraTarget = cameraGoal()
        camera.look(at: cameraTarget, from: cameraTarget + cameraBack * cameraDistance, relativeTo: nil)
    }

    /// Поворот камеры: она смотрит туда, куда уходит трасса впереди, а не куда повёрнута машина.
    /// Пока палец на экране, поворот медленнее, чтобы нарисованная линия не «уезжала» из-под пальца.
    func updateCameraYaw(dt: Float) {
        let ahead = trackAheadYaw()
        if abs(wrapAngle(ahead - cameraGoalYaw)) > cameraYawThreshold {
            cameraGoalYaw = ahead
        }
        let diff = wrapAngle(cameraGoalYaw - cameraYaw)
        let maxRate: Float = (finger == nil ? 90 : 35) * .pi / 180
        let smooth = diff * (1 - exp(-dt / 0.5))
        cameraYaw = wrapAngle(cameraYaw + simd_clamp(smooth, -maxRate * dt, maxRate * dt))
    }

    /// Сдвиг камеры, нужный, чтобы точка `world` оказалась внутри области экрана `zone` (доли экрана).
    func shiftToKeep(_ world: SIMD2<Float>, in zone: CGRect) -> SIMD3<Float>? {
        let point = SIMD3(world.x, 0, world.y)
        guard let screen = arView.project(point) else { return nil }
        let b = arView.bounds
        let rect = CGRect(x: b.width * zone.minX, y: b.height * zone.minY,
                          width: b.width * zone.width, height: b.height * zone.height)
        let clamped = CGPoint(x: min(max(screen.x, rect.minX), rect.maxX), y: min(max(screen.y, rect.minY), rect.maxY))
        guard clamped != screen, let ground = groundPoint(clamped) else { return nil }
        return point - SIMD3(ground.x, 0, ground.y)
    }

    /// Без пальца камера плавно следует за участком трассы впереди машины.
    /// С пальцем камера не едет сама (иначе точка под пальцем «уезжала» бы вместе с ней и машина не
    /// останавливалась), а только сдвигается, чтобы: 1) трасса на ~110 м вперёд оставалась в кадре,
    /// 2) машина держалась в нижней трети экрана. Второе важнее, поэтому применяется последним.
    func updateCamera(dt: Float) {
        updateCameraYaw(dt: dt)
        if finger == nil {
            cameraTarget += (cameraGoal() - cameraTarget) * (1 - exp(-dt / 0.3))
        } else {
            let ahead = track.frame(atDistance: carTrackDistance + 110).position
            if let shift = shiftToKeep(ahead, in: CGRect(x: 0.1, y: 0.08, width: 0.8, height: 0.8)) {
                cameraTarget += shift * (1 - exp(-dt / 0.25))
            }
            camera.look(at: cameraTarget, from: cameraTarget + cameraBack * cameraDistance, relativeTo: nil)
            if let shift = shiftToKeep(follower.position, in: CGRect(x: 0.12, y: 0.66, width: 0.76, height: 0.22)) {
                cameraTarget += shift * (1 - exp(-dt / 0.12))
            }
        }
        camera.look(at: cameraTarget, from: cameraTarget + cameraBack * cameraDistance, relativeTo: nil)
    }
}
