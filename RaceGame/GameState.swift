import Observation

/// Данные для HUD. Обновляется игровым циклом ~10 раз в секунду.
@Observable
final class GameState {
    var speedKmh = 0
    var laps = 0
    var currentLapTime: Double = 0
    var bestLap: Double?
    var offTrack = false
    var wrongWay = false
    var hasTouched = false
    var isLoading = true
    /// Положение машины (x, z) для мини-карты.
    var carPosition: SIMD2<Float> = .zero
    /// Курс камеры — мини-карта поворачивается вместе с ней.
    var cameraYaw: Float = 0

    func reset() {
        speedKmh = 0
        laps = 0
        currentLapTime = 0
        bestLap = nil
        offTrack = false
        wrongWay = false
        hasTouched = false
    }
}
