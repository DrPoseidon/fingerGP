import SwiftUI

/// Кнопка товара в гараже: «Выбрано» / «Выбрать» / цена (тусклая, если монет не хватает).
struct PurchaseButton: View {
    let selected: Bool
    let owned: Bool
    let price: Int
    let canAfford: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if selected {
                    Label("Выбрано", systemImage: "checkmark")
                } else if owned {
                    Text("Выбрать")
                } else {
                    HStack(spacing: 5) {
                        CoinIcon(size: 16)
                        Text("\(price)").monospacedDigit()
                    }
                }
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? Color.white.opacity(0.12) : owned ? Theme.raceBlue : Theme.brandRed, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selected || (!owned && !canAfford))
        .opacity(!selected && !owned && !canAfford ? 0.45 : 1)
    }
}
