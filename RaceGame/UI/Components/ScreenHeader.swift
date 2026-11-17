import SwiftUI

/// Шапка экрана: «назад», заголовок и необязательный элемент справа.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            CircleButton(systemName: "chevron.left", action: onBack)
            Text(title)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            trailing()
        }
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack) { EmptyView() }
    }
}
