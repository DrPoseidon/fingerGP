import Foundation
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
    /// Подсказку «Веди пальцем…» видят только в первых `hintRaces` гонках (гонка считается, если игрок коснулся экрана).
    private(set) var showHint = GameState.hintNeeded
    private static let hintRacesKey = "hint.racesWithTouch"
    private static let hintRaces = 3
    private static var hintNeeded: Bool { UserDefaults.standard.integer(forKey: hintRacesKey) < hintRaces }
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
    /// Стартовые огни при старте с хода: сколько красных горит или зелёный; nil — не показывать.
    var startLights: StartLights?

    /// Первое касание в гонке — подсказка больше не нужна, гонка засчитывается в счётчик подсказок.
    func markTouched() {
        guard !hasTouched else { return }
        hasTouched = true
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: GameState.hintRacesKey) + 1, forKey: GameState.hintRacesKey)
    }

    func reset() {
        speedKmh = 0
        laps = 0
        currentLapTime = 0
        bestLap = nil
        offTrack = false
        wrongWay = false
        hasTouched = false
        showHint = GameState.hintNeeded
        ghostPosition = nil
        lapInvalid = false
        delta = nil
        banner = nil
        startLights = nil
    }
}

enum StartLights: Equatable {
    case red(Int)
    case green
}
