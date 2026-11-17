import SwiftUI
import RealityKit
import Combine
import os

struct GameView: UIViewRepresentable {
    let track: TrackDefinition
    let mode: GameMode
    let state: GameState
    /// Увеличивается при нажатии «перезапуск».
    let restartToken: Int

    func makeCoordinator() -> GameController { GameController(definition: track, mode: mode, state: state) }
    func makeUIView(context: Context) -> ARView { context.coordinator.makeView() }
    static func dismantleUIView(_ uiView: ARView, coordinator: GameController) { coordinator.shutdown() }
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.restartIfNeeded(token: restartToken)
    }
}
