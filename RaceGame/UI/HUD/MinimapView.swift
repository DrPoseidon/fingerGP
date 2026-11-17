import SwiftUI
import simd

/// Силуэт трассы для мини-карты. Поворачивается вместе с камерой гонки, поэтому вписывается
/// в квадрат по описанной окружности — при любом повороте карта не вылезает за рамку.
@MainActor
struct Minimap {
    static let size: CGFloat = 130

    let points: [SIMD2<Float>]
    let start: SIMD2<Float>
    /// Границы секторов (те же отсечки, что в LapTimer): точка на осевой и направление трассы.
    let sectorMarks: [(point: SIMD2<Float>, tangent: SIMD2<Float>)]
    private let center: SIMD2<Float>
    private let radius: Float

    private static var cache: [TrackID: Minimap] = [:]

    static func get(_ id: TrackID) -> Minimap {
        if let cached = cache[id] { return cached }
        let map = Minimap(track: Track(TrackDefinition.get(id)))
        cache[id] = map
        return map
    }

    private init(track: Track) {
        let pts = stride(from: 0, to: track.points.count, by: 3).map { track.points[$0] }
        points = pts
        start = track.points[0]
        let n = track.points.count
        sectorMarks = (1..<LapTimer.sectorCount).map { k in
            let i = n * k / LapTimer.sectorCount
            return (track.points[i], track.tangents[i])
        }
        let lo = pts.reduce(pts[0]) { simd_min($0, $1) }, hi = pts.reduce(pts[0]) { simd_max($0, $1) }
        center = (lo + hi) / 2
        radius = pts.map { simd_distance($0, (lo + hi) / 2) }.max()!
    }

    /// Мировая точка (x, z) → точка внутри `rect` с учётом курса камеры: «вверх» на карте — вперёд для камеры.
    func project(_ p: SIMD2<Float>, yaw: Float, in rect: CGRect) -> CGPoint {
        let f = SIMD2(sin(yaw), cos(yaw))
        let d = p - center
        let scale = Float(min(rect.width, rect.height)) / 2 / radius
        return CGPoint(x: rect.midX + CGFloat((-f.y * d.x + f.x * d.y) * scale),
                       y: rect.midY + CGFloat(-(f.x * d.x + f.y * d.y) * scale))
    }
}

struct MinimapView: View {
    let track: TrackDefinition
    let state: GameState

    var body: some View {
        let map = Minimap.get(track.id)
        let car = state.carPosition, yaw = state.cameraYaw
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
            var path = Path()
            if let first = map.points.first {
                path.move(to: map.project(first, yaw: yaw, in: rect))
                for p in map.points.dropFirst() { path.addLine(to: map.project(p, yaw: yaw, in: rect)) }
                path.closeSubpath()
            }
            context.stroke(path, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            // Границы секторов — жёлтые штрихи поперёк трассы.
            for mark in map.sectorMarks {
                let p = map.project(mark.point, yaw: yaw, in: rect)
                let ahead = map.project(mark.point + mark.tangent * 20, yaw: yaw, in: rect)
                let dx = ahead.x - p.x, dy = ahead.y - p.y
                let len = max(hypot(dx, dy), 0.001)
                let nx = -dy / len * 7, ny = dx / len * 7
                var tick = Path()
                tick.move(to: CGPoint(x: p.x - nx, y: p.y - ny))
                tick.addLine(to: CGPoint(x: p.x + nx, y: p.y + ny))
                context.stroke(tick, with: .color(Theme.gold),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            let start = map.project(map.start, yaw: yaw, in: rect)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(.black))

            // Призрак лучшего круга — полупрозрачная белая точка.
            if let ghost = state.ghostPosition {
                let g = map.project(ghost, yaw: yaw, in: rect)
                context.fill(Path(ellipseIn: CGRect(x: g.x - 5, y: g.y - 5, width: 10, height: 10)),
                             with: .color(.white.opacity(0.55)))
            }

            // Призрак медали-цели — точка цвета медали.
            if let medalGhost = state.medalGhostPosition, let medal = state.medalTarget?.medal {
                let g = map.project(medalGhost, yaw: yaw, in: rect)
                context.fill(Path(ellipseIn: CGRect(x: g.x - 5, y: g.y - 5, width: 10, height: 10)),
                             with: .color(Color(medal.color).opacity(0.8)))
            }

            // Соперники — точки своих цветов.
            for o in state.opponents {
                let p = map.project(o.position, yaw: yaw, in: rect)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(Color(o.color)))
            }

            let dot = map.project(car, yaw: yaw, in: rect)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                         with: .color(Color(red: 0.9, green: 0.12, blue: 0.12)))
        }
        .frame(width: Minimap.size, height: Minimap.size)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}
