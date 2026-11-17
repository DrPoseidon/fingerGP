import SwiftUI
import simd

@main
struct RaceGameApp: App {
    init() {
        LapRecords.dropLegacyRecords()
        LapRecords.dropRemovedTracks()
        LapRecords.seedChallengeRecords()
        MedalStore.shared.prepare()
        // Модель машины грузится сразу при запуске, параллельно с показом меню.
        Task { @MainActor in _ = try? await CarEntity.load(scale: 1) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

enum Screen: Equatable {
    case menu, modeSelect, trackSelect, garage
    case race(TrackID, GameMode)
}

struct RootView: View {
    @State private var screen: Screen = Screen.initial
    /// Режим, выбранный на экране режимов, — с ним открывается выбранная трасса.
    @State private var mode: GameMode = Screen.debugMode
    /// 3D-фон меню создаётся после первого кадра: его создание (сцена RealityKit, шейдеры, музыка) занимает
    /// пару секунд, и без этого всё это время был бы тёмный экран вместо меню.
    @State private var backgroundReady = false

    var body: some View {
        ZStack {
            switch screen {
            case .menu, .modeSelect, .trackSelect:
                // Фон с пролётом общий для меню и выбора трассы, чтобы не перезапускался при переходе.
                Group {
                    if backgroundReady {
                        FlyoverView()
                    } else {
                        Color("LaunchBackground")
                    }
                }
                .ignoresSafeArea()
                .overlay(LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.55)],
                                        startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                .task {
                    // Дать меню отрисоваться, затем строить сцену.
                    try? await Task.sleep(for: .milliseconds(150))
                    backgroundReady = true
                }
                if screen == .menu {
                    MenuView(onPlay: { withAnimation(.easeInOut(duration: 0.3)) { screen = .modeSelect } },
                             onGarage: { withAnimation(.easeInOut(duration: 0.3)) { screen = .garage } })
                        .transition(.opacity)
                } else if screen == .modeSelect {
                    ModeSelectView(
                        onBack: { withAnimation(.easeInOut(duration: 0.3)) { screen = .menu } },
                        onSelect: { selected in
                            mode = selected
                            withAnimation(.easeInOut(duration: 0.3)) { screen = .trackSelect }
                        })
                        .transition(.opacity)
                } else {
                    TrackSelectView(
                        mode: mode,
                        onBack: { withAnimation(.easeInOut(duration: 0.3)) { screen = .modeSelect } },
                        onSelect: { screen = .race($0, mode) })
                        .transition(.opacity)
                }
            case .race(let id, let mode):
                RaceView(track: TrackDefinition.get(id), mode: mode) { screen = .menu }
            case .garage:
                GarageView { withAnimation(.easeInOut(duration: 0.3)) { screen = .menu } }
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

extension Screen {
    /// Для отладки: `-autopilot` или `-track <id>` сразу открывают заезд (по умолчанию — Гавань),
    /// `-race` — в режиме гонки, `-screen select` — экран выбора трассы.
    /// `-race` / `-challenge` — режим для отладочного запуска.
    static var debugMode: GameMode {
        DebugFlags.has("-race") ? .race : DebugFlags.has("-challenge") ? .challenge : .training
    }

    static var initial: Screen {
        switch DebugFlags.value("-screen") {
        case "select": return .trackSelect
        case "mode": return .modeSelect
        case "garage": return .garage
        default: break
        }
        guard DebugFlags.has("-autopilot") || DebugFlags.has("-track") else { return .menu }
        let id = DebugFlags.value("-track").flatMap(TrackID.init(rawValue:)) ?? .harbor
        return .race(id, debugMode)
    }
}
