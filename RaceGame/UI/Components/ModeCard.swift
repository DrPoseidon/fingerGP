import SwiftUI

struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var color = Theme.brandRed
    var locked = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 64, height: 64)
                .background(locked ? Color.white.opacity(0.12) : color,
                            in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                    if locked {
                        Text("СКОРО")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.yellow.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .opacity(locked ? 0.55 : 1)
        .padding(14)
        .glassPanel(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityHint(locked ? "Режим появится позже" : "")
    }
}
