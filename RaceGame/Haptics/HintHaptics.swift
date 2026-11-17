import UIKit
import CoreHaptics

/// Вибрация подсказки жестом: Core Haptics умеет непрерывную вибрацию нужной длины, UIKit — только толчки.
@MainActor
final class HintHaptics {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
    }

    /// Касание: короткий чёткий щелчок.
    func tap() {
        play(CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
        ], relativeTime: 0))
    }

    /// Ведение пальца: едва заметная непрерывная вибрация — плавно нарастает и затухает.
    func swipe(duration: Double) {
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.22),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
        ], relativeTime: 0, duration: duration)
        let envelope = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.3),
            .init(relativeTime: duration * 0.3, value: 1),
            .init(relativeTime: duration * 0.7, value: 1),
            .init(relativeTime: duration, value: 0),
        ], relativeTime: 0)
        play(event, curves: [envelope])
    }

    private func play(_ event: CHHapticEvent, curves: [CHHapticParameterCurve] = []) {
        guard let engine, let pattern = try? CHHapticPattern(events: [event], parameterCurves: curves) else { return }
        try? engine.start()
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }
}
