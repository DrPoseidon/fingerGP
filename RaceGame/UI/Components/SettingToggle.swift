import SwiftUI

/// Переключатель настройки: жирный заголовок и необязательное пояснение под ним.
struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isOn) {
                Text(title).font(.system(size: 17, weight: .bold))
            }
            .tint(Theme.brandRed)
            if let note {
                SettingNote(text: note)
            }
        }
    }
}

/// Мелкое серое пояснение к настройке.
struct SettingNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
