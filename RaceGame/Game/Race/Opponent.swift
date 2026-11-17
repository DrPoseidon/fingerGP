import UIKit
import simd

/// Соперник: та же физика, что у игрока; его «палец» едет по трассе впереди машины со скоростью
/// из профиля, умноженной на мастерство.
struct Opponent {
    let name: String
    let color: UIColor
    /// Доля от предельной скорости в поворотах (0.8…0.95).
    let skill: Float
    var follower: CarFollower
    var car: CarEntity?
    /// Пройденная дистанция гонки от линии старта (на стартовой решётке — отрицательная).
    var progress: Float
    var trackIndex: Int
    /// Смещение от осевой: базовое (своя полоса), желаемое (для обгона) и текущее.
    let baseLane: Float
    var lane: Float
    var laneNow: Float
    var virtualFinger: VirtualFinger
    var finger: SIMD2<Float>?
    /// Задержка реакции на зелёный.
    var reaction: Float
    var throttle: Float = 0
    var finishTime: Double?
    /// Прозрачность модели: падает, пока игрок проезжает сквозь машину.
    var opacity: Float = 1
}

/// Строка итоговой таблицы.
struct RaceResult: Identifiable, Equatable {
    let id: Int
    let position: Int
    let name: String
    let color: UIColor
    let isPlayer: Bool
    /// Время финиша (у тех, кто ещё не доехал, — оценка по средней скорости).
    let time: Double
}
