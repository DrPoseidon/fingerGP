import Foundation

/// Время круга в виде «1:23.45».
func formatLapTime(_ t: Double) -> String {
    String(format: "%d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
}

/// Разница с лучшим кругом: «−0.32» / «+0.15».
func formatDelta(_ d: Double) -> String {
    String(format: "%@%.2f", d < 0 ? "−" : "+", abs(d))
}
