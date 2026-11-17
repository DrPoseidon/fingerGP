import SwiftUI
import RealityKit
import Combine
import os

/// Общие настройки сцены для гонки и фона меню.
@MainActor
enum SceneSetup {
    static func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.55, green: 0.75, blue: 0.92, alpha: 1))
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        return view
    }

    static func makeSun() -> DirectionalLight {
        let sun = DirectionalLight()
        sun.light.intensity = 4000
        var shadow = DirectionalLightComponent.Shadow()
        shadow.shadowProjection = .automatic(maximumDistance: 200)
        shadow.depthBias = 3
        sun.shadow = shadow
        sun.look(at: .zero, from: [-30, 60, 25], relativeTo: nil)
        return sun
    }
}
