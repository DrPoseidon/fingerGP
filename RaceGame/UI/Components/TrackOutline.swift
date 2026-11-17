import SwiftUI

/// Силуэт трассы для карточки (кэшируется, чтобы не пересчитывать сплайн при каждой перерисовке).
@MainActor
enum TrackPreview {
    private static var cache: [TrackID: (points: [CGPoint], length: Float)] = [:]

    static func get(_ id: TrackID) -> (points: [CGPoint], length: Float) {
        if let cached = cache[id] { return cached }
        let track = Track(TrackDefinition.get(id))
        let points = stride(from: 0, to: track.points.count, by: 4).map {
            CGPoint(x: CGFloat(track.points[$0].x), y: CGFloat(track.points[$0].y))
        }
        let result = (points, track.length)
        cache[id] = result
        return result
    }
}

struct TrackOutline: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let scale = min(rect.width / (maxX - minX), rect.height / (maxY - minY))
        let offset = CGPoint(x: rect.midX - (minX + maxX) / 2 * scale, y: rect.midY - (minY + maxY) / 2 * scale)
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y) }
        var path = Path()
        path.move(to: map(first))
        for p in points.dropFirst() { path.addLine(to: map(p)) }
        path.closeSubpath()
        return path
    }
}
