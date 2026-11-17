import Foundation
import CoreGraphics
import UIKit
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
    /// Машина давно стоит без пальца на экране — показать анимацию «веди пальцем».
    var showGestureHint = false
    /// Путь пальца подсказки — точки трассы впереди машины в координатах экрана.
    var gestureHintPath: [CGPoint] = []
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

    /// Средний FPS и самый долгий кадр (мс) за последние полсекунды; nil — счётчик выключен.
    var fps: (average: Double, worstMs: Double)?

    /// Сколько монет только что заработано (всплывает в HUD).
    var coinToast: Int?
    /// Награда за гонку — в итоговой таблице.
    var raceReward = 0
    /// Следующая медаль-цель в тренировке и её время.
    var medalTarget: (medal: Medal, time: Double)?
    /// Призрак-цель на мини-карте.
    var medalGhostPosition: SIMD2<Float>?

    // Гонка против соперников.
    var mode: GameMode = .training
    var lapsTotal = 0
    /// Текущий круг гонки (с 1), место в гонке и время с зелёного (со штрафами).
    var raceLap = 1
    var racePosition = RaceSession.carCount
    var raceTime: Double = 0
    /// Сила слипстрима 0…1 (для значка в HUD).
    var draft: Float = 0
    /// Итоговая таблица — показывается после финиша.
    var raceResults: [RaceResult]?
    /// Соперники на мини-карте.
    var opponents: [MinimapCar] = []

    func reset() {
        speedKmh = 0
        laps = 0
        currentLapTime = 0
        bestLap = nil
        offTrack = false
        wrongWay = false
        hasTouched = false
        showGestureHint = false
        showHint = GameState.hintNeeded
        ghostPosition = nil
        medalGhostPosition = nil
        lapInvalid = false
        delta = nil
        banner = nil
        startLights = nil
        raceLap = 1
        racePosition = RaceSession.carCount
        raceTime = 0
        raceResults = nil
        coinToast = nil
        raceReward = 0
        draft = 0
        opponents = []
    }
}

enum StartLights: Equatable {
    case red(Int)
    case green
}

struct MinimapCar {
    let position: SIMD2<Float>
    let color: UIColor
}
