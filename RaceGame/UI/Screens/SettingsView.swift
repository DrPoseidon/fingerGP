import SwiftUI

struct SettingsView: View {
    @AppStorage(RaceSettings.offTrackRuleKey) private var offTrackRule = OffTrackRule.invalidate.rawValue
    @AppStorage(RaceSettings.resetToTrackKey) private var resetToTrack = false
    @AppStorage(RaceSettings.rollingStartKey) private var rollingStart = true
    @AppStorage(RaceSettings.showFPSKey) private var showFPS = false
    @AppStorage(RaceSettings.collisionsKey) private var collisions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Настройки")
                .font(.system(size: 28, weight: .heavy, design: .rounded))

            VStack(alignment: .leading, spacing: 8) {
                Text("Выезд за трассу")
                    .font(.system(size: 17, weight: .bold))
                Picker("Выезд за трассу", selection: $offTrackRule) {
                    ForEach(OffTrackRule.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                SettingNote(text: offTrackRule == OffTrackRule.ignore.rawValue
                            ? "Круг засчитывается, даже если срезать по траве."
                            : "Круг не засчитывается, если машина дольше секунды за поребриком или в сумме больше 3 секунд за круг.")
            }

            SettingToggle(title: "Возвращать на трассу", isOn: $resetToTrack,
                          note: offTrackRule == OffTrackRule.invalidate.rawValue
                          ? "Через полсекунды за поребриком экран затемняется и машина появляется на трассе там, где съехала. Круг не засчитывается."
                          : String(format: "Через полсекунды за поребриком экран затемняется, машина появляется на трассе там, где съехала, а к времени круга добавляется штраф +%.0f с.", RaceSettings.resetPenalty))
            SettingToggle(title: "Старт с хода", isOn: $rollingStart)
            SettingToggle(title: "Столкновения в гонке", isOn: $collisions)
            SettingToggle(title: "Показывать FPS", isOn: $showFPS)
            Spacer()
        }
        .padding(24)
        .padding(.top, 8)
    }
}
