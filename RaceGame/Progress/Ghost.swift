import Foundation
import simd

/// Запись круга: положение, курс и скорость машины через равные промежутки времени.
struct Ghost {
    static let interval: Double = 0.05          // 20 раз в секунду

    /// (x, z, курс, скорость) на моменты 0, interval, 2·interval, …
    var samples: [SIMD4<Float>] = []

    var duration: Double { Double(max(samples.count - 1, 0)) * Ghost.interval }

    /// Положение на момент `t` с начала круга (линейная интерполяция), nil — запись закончилась.
    func pose(at t: Double) -> (position: SIMD2<Float>, heading: Float, speed: Float)? {
        let x = t / Ghost.interval
        let i = Int(x)
        guard i >= 0, i + 1 < samples.count else { return nil }
        let a = samples[i], b = samples[i + 1]
        let k = Float(x - Double(i))
        let heading = a.z + wrapAngle(b.z - a.z) * k
        return (SIMD2(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k), heading, a.w + (b.w - a.w) * k)
    }

    private static func url(for id: TrackID) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("ghosts", isDirectory: true).appendingPathComponent("\(id.rawValue).bin")
    }

    static func load(for id: TrackID) -> Ghost? {
        guard let url = url(for: id), let data = try? Data(contentsOf: url),
              data.count >= MemoryLayout<SIMD4<Float>>.stride * 2 else { return nil }
        let count = data.count / MemoryLayout<SIMD4<Float>>.stride
        let samples = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: SIMD4<Float>.self).prefix(count))
        }
        return Ghost(samples: samples)
    }

    static func exists(for id: TrackID) -> Bool {
        guard let url = url(for: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func delete(for id: TrackID) {
        if let url = url(for: id) { try? FileManager.default.removeItem(at: url) }
    }

    func save(for id: TrackID) {
        guard let url = Ghost.url(for: id) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: url, options: .atomic)
    }
}
