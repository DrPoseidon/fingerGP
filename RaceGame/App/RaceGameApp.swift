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

    var body: some View {
        ZStack {
            switch screen {
            case .menu, .modeSelect, .trackSelect:
                // Фон с пролётом общий для меню и выбора трассы, чтобы не перезапускался при переходе.
                FlyoverView()
                    .ignoresSafeArea()
                    .overlay(LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.55)],
                                            startPoint: .top, endPoint: .bottom).ignoresSafeArea())
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
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-race") ? .race : args.contains("-challenge") ? .challenge : .training
    }

    static var initial: Screen {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-screen"), i + 1 < args.count {
            if args[i + 1] == "select" { return .trackSelect }
            if args[i + 1] == "mode" { return .modeSelect }
            if args[i + 1] == "garage" { return .garage }
        }
        guard args.contains("-autopilot") || args.contains("-track") else { return .menu }
        let mode = debugMode
        if let i = args.firstIndex(of: "-track"), i + 1 < args.count, let id = TrackID(rawValue: args[i + 1]) {
            return .race(id, mode)
        }
        return .race(.harbor, mode)
    }
}
