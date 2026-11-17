import SwiftUI

struct CircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
