/// Хронометраж и честный зачёт круга.
///
/// Трасса делится на `sectorCount` секторов отсечками по осевой линии. Круг засчитывается, только если
/// машина прошла все отсечки по порядку и не срезала по траве: одна вылазка за поребрик дольше
/// `maxOffTrackStreak` секунд или в сумме дольше `maxOffTrackTotal` — круг не засчитывается
/// (по траве можно срезать только так, а на нормальной траектории вылеты короткие).
struct LapTimer {
    enum Event: Equatable {
        /// Пересечена линия старта — пошёл новый круг.
        case lapStarted
        /// Пройдена отсечка сектора `index` (0…sectorCount−2) на времени `time` от начала круга.
        case sector(index: Int, time: Double)
        /// Круг закончен. `splits` — время на отсечках, `valid` — засчитан ли.
        case lapFinished(time: Double, splits: [Double], valid: Bool)
        /// Круг перестал быть честным (срезка) — сообщается один раз за круг.
        case invalidated
    }

    static let sectorCount = 3
    let maxOffTrackStreak: Double = 1.0
    let maxOffTrackTotal: Double = 3.0

    private let pointCount: Int
    private let boundaries: [Int]
    private var prevProgress: Int

    private(set) var isRunning = false
    private(set) var isValid = true
    private(set) var lapTime: Double = 0
    private(set) var splits: [Double] = []
    private var offStreak: Double = 0
    private var offTotal: Double = 0

    /// - Parameters:
    ///   - pointCount: число точек осевой линии; индекс 0 — линия старта.
    ///   - startProgress: индекс ближайшей к машине точки на старте.
    init(pointCount: Int, startProgress: Int) {
        self.pointCount = pointCount
        boundaries = (1..<LapTimer.sectorCount).map { pointCount * $0 / LapTimer.sectorCount }
        prevProgress = startProgress
    }

    /// Вызывать каждый кадр. `progress` — индекс ближайшей точки осевой линии.
    mutating func update(progress: Int, offTrack: Bool, dt: Double) -> [Event] {
        var events: [Event] = []
        let n = pointCount
        let prev = prevProgress
        prevProgress = progress

        if isRunning {
            lapTime += dt
            if offTrack {
                offStreak += dt
                offTotal += dt
            } else {
                offStreak = 0
            }
            if isValid && (offStreak > maxOffTrackStreak || offTotal > maxOffTrackTotal) {
                isValid = false
                events.append(.invalidated)
            }
        }

        // Отсечки: вперёд — засчитать следующую, назад — откатить последнюю (машина развернулась).
        let step = progress - prev
        if isRunning && abs(step) < n / 4 {
            if splits.count < boundaries.count, prev < boundaries[splits.count], progress >= boundaries[splits.count] {
                splits.append(lapTime)
                events.append(.sector(index: splits.count - 1, time: lapTime))
            } else if let last = splits.indices.last, prev >= boundaries[last], progress < boundaries[last] {
                splits.removeLast()
            }
        }

        // Линия старта: переход с последней четверти трассы на первую — вперёд, наоборот — назад.
        let crossedForward = prev > n * 3 / 4 && progress < n / 4
        let crossedBackward = prev < n / 4 && progress > n * 3 / 4
        if crossedForward {
            if isRunning && splits.count == boundaries.count {
                events.append(.lapFinished(time: lapTime, splits: splits, valid: isValid))
            } else if isRunning && !splits.isEmpty {
                // Отсечки пройдены не все — так к старту можно попасть только срезав.
                events.append(.lapFinished(time: lapTime, splits: splits, valid: false))
            }
            startLap()
            events.append(.lapStarted)
        } else if crossedBackward && isRunning && splits.isEmpty {
            // Сдал назад за линию старта — круг ещё не начат.
            isRunning = false
            lapTime = 0
        }
        return events
    }

    private mutating func startLap() {
        isRunning = true
        isValid = true
        lapTime = 0
        splits = []
        offStreak = 0
        offTotal = 0
    }
}
