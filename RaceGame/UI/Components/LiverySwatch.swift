import SwiftUI

/// Образец ливреи: основной цвет — большой круг, второй и акцент — половинки внутреннего.
struct LiverySwatch: View {
    let livery: Livery
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(Color(livery.primary))
            Circle().trim(from: 0, to: 0.5).fill(Color(livery.secondary)).rotationEffect(.degrees(-45))
                .padding(size * 0.22)
            Circle().trim(from: 0.5, to: 1).fill(Color(livery.accent)).rotationEffect(.degrees(-45))
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
    }
}
