import SwiftUI

/// Подсказка жестом, когда машина долго стоит: палец касается экрана над машиной (расходится круг)
/// и ведёт вверх, оставляя след. Повторяется по кругу.
struct GestureHintView: View {
    /// Путь пальца на экране (точки трассы впереди машины); пустой — по центру, снизу вверх.
    let path: [CGPoint]
    private static let cycle = 2.7
    // Фазы цикла, с: появление, нажатие, ведение, исчезновение, дальше пауза.
    private static let pressAt = 0.3
    private static let moveAt = 0.55
    private static let moveDuration = 1.1
    /// Цикл отсчитывается от появления подсказки — первый показ начинается с касания, а не с середины.
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.cycle)
                let moveEnd = Self.moveAt + Self.moveDuration
                let appear = min(max(t / Self.pressAt, 0), 1)
                let press = min(max((t - Self.pressAt) / 0.15, 0), 1)
                let move = smoothstep((t - Self.moveAt) / Self.moveDuration)
                let fade = 1 - min(max((t - moveEnd) / 0.4, 0), 1)
                let ripple = min(max((t - Self.pressAt) / 0.6, 0), 1)
                let points = path.count >= 2 ? path : [
                    CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.62),
                    CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.62 - 170),
                ]
                let trail = prefix(of: points, fraction: move)
                let tip = trail.last ?? points[0]

                ZStack {
                    // След пальца — по пройденной части пути.
                    Path { p in p.addLines(trail) }
                        .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    // Круг от касания.
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 26 + 50 * ripple, height: 26 + 50 * ripple)
                        .opacity((1 - ripple) * (press > 0 ? 1 : 0))
                        .position(points[0])
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 22, height: 22)
                        .opacity(press)
                        .position(tip)
                    // Рука: кончик указательного пальца — в точке касания.
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                        .scaleEffect(1 - 0.12 * press, anchor: .topLeading)
                        .position(x: tip.x + 26, y: tip.y + 34)
                }
                .opacity(appear * fade)
            }
        }
        .ignoresSafeArea()
        .task { await playHaptics() }
    }

    /// Вибрация в такт анимации: короткий щелчок на касании, непрерывная — пока палец ведёт.
    private func playHaptics() async {
        let haptics = HintHaptics()
        var cycleStart = start
        func wait(until offset: Double) async {
            let delay = cycleStart.addingTimeInterval(offset).timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        }
        while !Task.isCancelled {
            await wait(until: Self.pressAt)
            if Task.isCancelled { break }
            haptics.tap()
            await wait(until: Self.moveAt)
            if Task.isCancelled { break }
            haptics.swipe(duration: Self.moveDuration)
            cycleStart = cycleStart.addingTimeInterval(Self.cycle)
            await wait(until: 0)
        }
    }

    /// Начальная часть ломаной длиной `fraction` от всей длины.
    private func prefix(of points: [CGPoint], fraction: Double) -> [CGPoint] {
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var remaining = lengths.reduce(0, +) * fraction
        var out = [points[0]]
        for (i, len) in lengths.enumerated() {
            if remaining >= len {
                out.append(points[i + 1])
                remaining -= len
            } else {
                let k = len > 0 ? remaining / len : 0
                out.append(CGPoint(x: points[i].x + (points[i + 1].x - points[i].x) * k,
                                   y: points[i].y + (points[i + 1].y - points[i].y) * k))
                break
            }
        }
        return out
    }

    private func smoothstep(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
