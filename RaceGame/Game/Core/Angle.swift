import Foundation

/// Угол, приведённый к (−π, π].
func wrapAngle(_ a: Float) -> Float {
    var a = a.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi }
    if a < -.pi { a += 2 * .pi }
    return a
}
