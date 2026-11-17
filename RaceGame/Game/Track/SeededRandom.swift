import RealityKit
import UIKit
import simd

/// Детерминированный ГПСЧ, чтобы расстановка декораций не менялась между запусками.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next(in range: ClosedRange<Float>) -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Float(state >> 40) / Float(1 << 24)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
