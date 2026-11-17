import SwiftUI

struct ModeSelectView: View {
    let onBack: () -> Void
    let onSelect: (GameMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Режим игры", onBack: onBack)
            Spacer()
            ForEach(GameMode.allCases) { mode in
                Button { onSelect(mode) } label: {
                    ModeCard(icon: mode.icon, title: mode.title, subtitle: mode.subtitle, color: mode.color)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}
