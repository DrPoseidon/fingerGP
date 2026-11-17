import SwiftUI
import RealityKit
import Combine

/// Монета: жёлтый кружок с ободком.
struct CoinIcon: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 1, green: 0.78, blue: 0.15))
            Circle().stroke(Color(red: 0.85, green: 0.55, blue: 0.05), lineWidth: size * 0.12)
                .padding(size * 0.14)
            Text("F")
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.75, green: 0.45, blue: 0.02))
        }
        .frame(width: size, height: size)
    }
}

/// Баланс или награда: «🪙 1 250» / «+ 🪙 25».
struct CoinBalance: View {
    let coins: Int
    var plus = false

    var body: some View {
        HStack(spacing: 6) {
            if plus { Text("+").font(.system(size: 18, weight: .black, design: .rounded)) }
            CoinIcon(size: 20)
            Text("\(coins)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

// MARK: - Гараж

struct GarageView: View {
    let onBack: () -> Void
    private var wallet: Wallet { Wallet.shared }
    @State private var tab = 0
    /// Что сейчас на подиуме: выбранное или то, что игрок смотрит перед покупкой.
    @State private var previewCar = Wallet.shared.car
    @State private var previewLivery = Wallet.shared.livery

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                CircleButton(systemName: "chevron.left", action: onBack)
                Text("Гараж")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Spacer()
                CoinBalance(coins: wallet.coins)
            }
            .padding(.top, 8)

            GaragePreview(car: previewCar, livery: previewLivery)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Picker("", selection: $tab) {
                Text("Машины").tag(0)
                Text("Ливреи").tag(1)
            }
            .pickerStyle(.segmented)

            ScrollView {
                if tab == 0 {
                    VStack(spacing: 10) {
                        ForEach(CarModel.all) { car in carCard(car) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(Livery.all) { livery in liveryCard(livery) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func carCard(_ car: CarModel) -> some View {
        let selected = wallet.selectedCar == car.id
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(car.name).font(.system(size: 20, weight: .heavy, design: .rounded))
                Text(car.subtitle).font(.system(size: 12, weight: .medium)).opacity(0.75)
                StatBar(title: "Разгон", value: car.acceleration)
                StatBar(title: "Скорость", value: car.topSpeed)
                StatBar(title: "Сцепление", value: car.grip)
            }
            Spacer(minLength: 0)
            actionButton(selected: selected, owned: wallet.owns(car: car), price: car.price) {
                wallet.buy(car: car)
            }
        }
        .padding(14)
        .background(Color.white.opacity(previewCar == car ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.white.opacity(0.7) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { previewCar = car }
    }

    private func liveryCard(_ livery: Livery) -> some View {
        let selected = wallet.selectedLivery == livery.id
        return VStack(spacing: 8) {
            // Три цвета: основной — большой круг, второй и акцент — половинки внутреннего.
            ZStack {
                Circle().fill(Color(livery.primary))
                Circle().trim(from: 0, to: 0.5).fill(Color(livery.secondary)).rotationEffect(.degrees(-45))
                    .padding(12)
                Circle().trim(from: 0.5, to: 1).fill(Color(livery.accent)).rotationEffect(.degrees(-45))
                    .padding(12)
            }
            .frame(width: 54, height: 54)
            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            Text(livery.name).font(.system(size: 15, weight: .bold, design: .rounded))
            actionButton(selected: selected, owned: wallet.owns(livery: livery), price: livery.price) {
                wallet.buy(livery: livery)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.white.opacity(previewLivery == livery ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.white.opacity(0.7) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { previewLivery = livery }
    }

    /// «Выбрано» / «Выбрать» / цена (серая, если монет не хватает).
    private func actionButton(selected: Bool, owned: Bool, price: Int, action: @escaping () -> Void) -> some View {
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
            .background(selected ? Color.white.opacity(0.12)
                        : owned ? Color(red: 0.16, green: 0.42, blue: 0.95)
                        : Color(red: 0.86, green: 0.13, blue: 0.13), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selected || (!owned && wallet.coins < price))
        .opacity(!selected && !owned && wallet.coins < price ? 0.45 : 1)
    }
}

/// Полоска характеристики: 1.0 — стандартная машина (середина шкалы).
struct StatBar: View {
    let title: String
    let value: Float

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(width: 70, alignment: .leading).opacity(0.8)
            GeometryReader { geo in
                let fraction = CGFloat(min(max((value - 0.85) / 0.3, 0.05), 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(value > 1.001 ? Color(red: 0.3, green: 0.9, blue: 0.45)
                                   : value < 0.999 ? Color(red: 1, green: 0.55, blue: 0.3) : .white.opacity(0.8))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(width: 110, height: 6)
        }
    }
}

/// Подиум гаража: машина в выбранной ливрее медленно вращается.
struct GaragePreview: UIViewRepresentable {
    let car: CarModel
    let livery: Livery

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.13, green: 0.15, blue: 0.2, alpha: 1))
        context.coordinator.setUp(view)
        context.coordinator.show(car: car, livery: livery)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.show(car: car, livery: livery)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator {
        private let turntable = Entity()
        private var shown: (car: String, livery: String)?
        private var subscription: Cancellable?
        private var loadTask: Task<Void, Never>?

        func setUp(_ view: ARView) {
            let anchor = AnchorEntity(world: .zero)
            view.scene.addAnchor(anchor)
            anchor.addChild(turntable)

            var floor = PhysicallyBasedMaterial()
            floor.baseColor = .init(tint: UIColor(red: 0.2, green: 0.22, blue: 0.28, alpha: 1))
            floor.roughness = 0.8
            let podium = ModelEntity(mesh: .generateCylinder(height: 0.1, radius: 3.2), materials: [floor])
            podium.position.y = -0.05
            anchor.addChild(podium)

            let sun = DirectionalLight()
            sun.light.intensity = 3500
            sun.look(at: .zero, from: [-3, 6, 4], relativeTo: nil)
            anchor.addChild(sun)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 40
            camera.look(at: [0, 0.4, 0], from: [4.2, 2.6, 5.2], relativeTo: nil)
            anchor.addChild(camera)

            subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.turntable.orientation *= simd_quatf(angle: Float(event.deltaTime) * 0.5, axis: [0, 1, 0])
                }
            }
        }

        func show(car: CarModel, livery: Livery) {
            guard shown?.car != car.id || shown?.livery != livery.id else { return }
            shown = (car.id, livery.id)
            loadTask?.cancel()
            loadTask = Task { [weak self] in
                guard let entity = try? await CarEntity.load(scale: 1, primary: livery.primary,
                                                             secondary: livery.secondary, accent: livery.accent,
                                                             model: car),
                      let self, !Task.isCancelled else { return }
                for child in self.turntable.children { child.removeFromParent() }
                self.turntable.addChild(entity.root)
            }
        }

        func stop() {
            subscription?.cancel()
            loadTask?.cancel()
        }
    }
}
