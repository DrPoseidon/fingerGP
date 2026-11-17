import SwiftUI

struct TrackSelectView: View {
    let mode: GameMode
    let onBack: () -> Void
    let onSelect: (TrackID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Выбор трассы", onBack: onBack)
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(TrackDefinition.all, id: \.id) { def in
                        let unlocked = MedalStore.shared.isUnlocked(def.id)
                        Button { onSelect(def.id) } label: { TrackCard(definition: def, mode: mode, unlocked: unlocked) }
                            .buttonStyle(.plain)
                            .disabled(!unlocked)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
    }
}
