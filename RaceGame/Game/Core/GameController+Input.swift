import SwiftUI
import RealityKit
import Combine
import os

/// Ввод: касания и точка на земле под пальцем.
extension GameController {
    @objc func handleTouch(_ gesture: UILongPressGestureRecognizer) {
        let point = groundPoint(gesture.location(in: arView))
        // Во время возврата на трассу касания не принимаются; после — нужно новое касание.
        if resetting || state.isPaused { finger = nil; return }
        // В гонке: до зелёного и после финиша касания не принимаются.
        if raceWaiting || raceFinished { finger = nil; return }
        // Во время отсчёта машина едет сама; после «Старт!» первое касание забирает управление.
        var phase = gesture.state
        if let runUp {
            guard runUp.green, phase == .began || phase == .changed else { return }
            self.runUp = nil
            phase = .began
        }
        switch phase {
        case .began:
            guard let point else { return }
            touchSuspended = false
            finger = point
            lastTouchLocation = gesture.location(in: arView)
            follower.touchBegan(at: point)
            state.markTouched()
        case .changed:
            if touchSuspended { return }
            // Микродрожание неподвижного пальца не пересчитывает точку: иначе она «ехала» бы вместе с камерой.
            let location = gesture.location(in: arView)
            guard let point, hypot(location.x - lastTouchLocation.x, location.y - lastTouchLocation.y) >= 3 else { return }
            lastTouchLocation = location
            finger = point
        default:
            finger = nil
            touchSuspended = false
        }
    }

    /// Точка на плоскости земли (y = 0) под пальцем, в координатах (x, z).
    func groundPoint(_ screen: CGPoint) -> SIMD2<Float>? {
        guard let ray = arView.ray(through: screen), ray.direction.y < -1e-4 else { return nil }
        let t = -ray.origin.y / ray.direction.y
        let p = ray.origin + ray.direction * t
        return SIMD2(p.x, p.z)
    }
}
