import SwiftUI

/// Счётчик кадров (настройка «Показывать FPS»). Самый долгий кадр больше ~25 мс — заметное подёргивание.
struct FPSBadge: View {
    let average: Double
    let worstMs: Double

    var body: some View {
        Text(String(format: "%.0f FPS · макс. кадр %.0f мс", average, worstMs))
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(average < 55 || worstMs > 25 ? .orange : .white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
    }
}
