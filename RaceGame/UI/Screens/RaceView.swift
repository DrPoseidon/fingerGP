import SwiftUI

struct RaceView: View {
    let track: TrackDefinition
    let mode: GameMode
    let onExit: () -> Void
    @State private var state = GameState()
    @State private var restartToken = 0
    @State private var muted = RaceAudio.isMuted
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            GameView(track: track, mode: mode, state: state, restartToken: restartToken)
                .ignoresSafeArea()
            HUDView(state: state, trackName: track.name)
                .allowsHitTesting(false)
            if state.showGestureHint && !state.isPaused {
                GestureHintView(path: state.gestureHintPath)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            VStack {
                Spacer()
                HStack {
                    MinimapView(track: track, state: state)
                    Spacer()
                }
            }
            .padding()
            .allowsHitTesting(false)
            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    CircleButton(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                        muted.toggle()
                        RaceAudio.isMuted = muted
                    }
                    if state.raceResults == nil {
                        CircleButton(systemName: "pause.fill") { state.isPaused = true }
                    } else {
                        CircleButton(systemName: "house.fill", action: onExit)
                    }
                }
                Spacer()
            }
            .padding()
            if state.isLoading {
                ProgressView("Загрузка…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .overlay {
            if state.isPaused {
                PauseView(onResume: { state.isPaused = false },
                          onRestart: { restartToken += 1 },
                          onExit: onExit)
                    .transition(.opacity)
            }
        }
        .overlay {
            if let results = state.raceResults {
                RaceResultsView(results: results, bestLap: state.bestLap, reward: state.raceReward,
                                onRestart: { restartToken += 1 }, onExit: onExit)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: state.showGestureHint)
        .animation(.easeOut(duration: 0.4), value: state.raceResults)
        .animation(.easeOut(duration: 0.2), value: state.isPaused)
        // Свернули игру или пришёл звонок — пауза, чтобы круг или гонка не шли без игрока.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && state.raceResults == nil && !state.isLoading { state.isPaused = true }
        }
    }
}
