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
    /// Положение призрака лучшего круга для мини-карты (nil — призрака сейчас нет).
    var ghostPosition: SIMD2<Float>?

    /// Текущий круг уже не будет засчитан (срезка по траве).
    var lapInvalid = false
    /// Отставание (+) или опережение (−) от лучшего круга на последней пройденной отсечке.
    var delta: Double?
    /// Подпись отсечки: «S1», «S2», «Круг».
    var deltaLabel = ""
    /// Короткое сообщение по центру: «Новый рекорд!», «Круг не засчитан».
    var banner: String?
    var bannerIsGood = false
    var bannerIcon = "xmark.octagon.fill"

    func reset() {
        speedKmh = 0
        laps = 0
        currentLapTime = 0
        bestLap = nil
        offTrack = false
        wrongWay = false
        hasTouched = false
        ghostPosition = nil
        lapInvalid = false
        delta = nil
        banner = nil
    }
}
