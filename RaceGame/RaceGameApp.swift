import SwiftUI
import simd

@main
struct RaceGameApp: App {
    init() {
        LapRecords.dropLegacyRecords()
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
    case menu, modeSelect, trackSelect
    case race(TrackID)
}

struct RootView: View {
    @State private var screen: Screen = Screen.initial

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
                    MenuView { withAnimation(.easeInOut(duration: 0.3)) { screen = .modeSelect } }
                        .transition(.opacity)
                } else if screen == .modeSelect {
                    ModeSelectView(
                        onBack: { withAnimation(.easeInOut(duration: 0.3)) { screen = .menu } },
                        onTraining: { withAnimation(.easeInOut(duration: 0.3)) { screen = .trackSelect } })
                        .transition(.opacity)
                } else {
                    TrackSelectView(
                        onBack: { withAnimation(.easeInOut(duration: 0.3)) { screen = .modeSelect } },
                        onSelect: { screen = .race($0) })
                        .transition(.opacity)
                }
            case .race(let id):
                RaceView(track: TrackDefinition.get(id)) { screen = .menu }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

extension Screen {
    /// Для отладки: `-autopilot` или `-track <id>` сразу открывают гонку (по умолчанию — Монца),
    /// `-screen select` — экран выбора трассы.
    static var initial: Screen {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-screen"), i + 1 < args.count {
            if args[i + 1] == "select" { return .trackSelect }
            if args[i + 1] == "mode" { return .modeSelect }
        }
        guard args.contains("-autopilot") || args.contains("-track") else { return .menu }
        if let i = args.firstIndex(of: "-track"), i + 1 < args.count, let id = TrackID(rawValue: args[i + 1]) {
            return .race(id)
        }
        return .race(.monza)
    }
}

// MARK: - Меню

struct MenuView: View {
    let onPlay: () -> Void
    @State private var muted = RaceAudio.isMuted
    /// `-screen settings` — открыть меню сразу с настройками (для скриншотов).
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("settings")

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 90)
            VStack(spacing: 6) {
                Text("FINGER GP")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .italic()
                Text("Веди пальцем — машина поедет следом")
                    .font(.system(size: 15, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
            Spacer()
            RecordsPanel()
                .padding(.bottom, 28)
            Button(action: onPlay) {
                Text("Играть")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 18)
                    .background(Color(red: 0.86, green: 0.13, blue: 0.13), in: Capsule())
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            Spacer().frame(height: 110)
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                CircleButton(systemName: "gearshape.fill") { showSettings = true }
                CircleButton(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    muted.toggle()
                    RaceAudio.isMuted = muted
                }
            }
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Статистика в меню: лучший круг и число кругов по каждой трассе.
struct RecordsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Лучшие круги")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .opacity(0.85)
            ForEach(TrackDefinition.all, id: \.id) { def in
                HStack(spacing: 10) {
                    TrackOutline(points: TrackPreview.get(def.id).points)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 30, height: 22)
                    Text(def.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer()
                    let laps = LapRecords.lapCount(def.id)
                    if laps > 0 {
                        Text("\(laps) кр.")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0.6)
                    }
                    Text(LapRecords.bestLap(def.id).map(formatLapTime) ?? "—:——.——")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .opacity(LapRecords.bestLap(def.id) == nil ? 0.45 : 1)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Настройки

struct SettingsView: View {
    @AppStorage(RaceSettings.offTrackRuleKey) private var offTrackRule = OffTrackRule.invalidate.rawValue
    @AppStorage(RaceSettings.resetToTrackKey) private var resetToTrack = false
    @AppStorage(RaceSettings.rollingStartKey) private var rollingStart = true

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
                Text(offTrackRule == OffTrackRule.ignore.rawValue
                     ? "Круг засчитывается, даже если срезать по траве."
                     : "Круг не засчитывается, если машина дольше секунды за поребриком или в сумме больше 3 секунд за круг.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $resetToTrack) {
                    Text("Возвращать на трассу")
                        .font(.system(size: 17, weight: .bold))
                }
                .tint(Color(red: 0.86, green: 0.13, blue: 0.13))
                Text(offTrackRule == OffTrackRule.invalidate.rawValue
                     ? "Через полсекунды за поребриком экран затемняется и машина появляется на трассе там, где съехала. Круг не засчитывается."
                     : String(format: "Через полсекунды за поребриком экран затемняется, машина появляется на трассе там, где съехала, а к времени круга добавляется штраф +%.0f с.", RaceSettings.resetPenalty))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $rollingStart) {
                Text("Старт с хода")
                    .font(.system(size: 17, weight: .bold))
            }
            .tint(Color(red: 0.86, green: 0.13, blue: 0.13))
            Spacer()
        }
        .padding(24)
        .padding(.top, 8)
    }
}

// MARK: - Выбор режима

struct ModeSelectView: View {
    let onBack: () -> Void
    let onTraining: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CircleButton(systemName: "chevron.left", action: onBack)
                Text("Режим игры")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.top, 8)
            Spacer()
            Button(action: onTraining) {
                ModeCard(icon: "stopwatch", title: "Тренировка",
                         subtitle: "Свободные круги в одиночку — оттачивай траекторию и ставь рекорды")
            }
            .buttonStyle(.plain)
            ModeCard(icon: "flag.checkered", title: "Гонка",
                     subtitle: "Заезд против соперников", locked: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var locked = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 64, height: 64)
                .background(locked ? Color.white.opacity(0.12) : Color(red: 0.86, green: 0.13, blue: 0.13),
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
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityHint(locked ? "Режим появится позже" : "")
    }
}

// MARK: - Выбор трассы

struct TrackSelectView: View {
    let onBack: () -> Void
    let onSelect: (TrackID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CircleButton(systemName: "chevron.left", action: onBack)
                Text("Выбор трассы")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.top, 8)
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(TrackDefinition.all, id: \.id) { def in
                        Button { onSelect(def.id) } label: { TrackCard(definition: def) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
    }
}

struct TrackCard: View {
    let definition: TrackDefinition

    var body: some View {
        let preview = TrackPreview.get(definition.id)
        HStack(spacing: 16) {
            TrackOutline(points: preview.points)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 110, height: 80)
                .padding(10)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                Text(definition.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(String(format: "%.2f км", preview.length / 1000))
                    if let best = LapRecords.bestLap(definition.id) {
                        Label(formatLapTime(best), systemImage: "stopwatch")
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .opacity(0.7)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }
}

/// Силуэт трассы для карточки (кэшируется, чтобы не пересчитывать сплайн при каждой перерисовке).
@MainActor
enum TrackPreview {
    private static var cache: [TrackID: (points: [CGPoint], length: Float)] = [:]

    static func get(_ id: TrackID) -> (points: [CGPoint], length: Float) {
        if let cached = cache[id] { return cached }
        let track = Track(TrackDefinition.get(id))
        let points = stride(from: 0, to: track.points.count, by: 4).map {
            CGPoint(x: CGFloat(track.points[$0].x), y: CGFloat(track.points[$0].y))
        }
        let result = (points, track.length)
        cache[id] = result
        return result
    }
}

struct TrackOutline: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let scale = min(rect.width / (maxX - minX), rect.height / (maxY - minY))
        let offset = CGPoint(x: rect.midX - (minX + maxX) / 2 * scale, y: rect.midY - (minY + maxY) / 2 * scale)
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y) }
        var path = Path()
        path.move(to: map(first))
        for p in points.dropFirst() { path.addLine(to: map(p)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Гонка

struct RaceView: View {
    let track: TrackDefinition
    let onExit: () -> Void
    @State private var state = GameState()
    @State private var restartToken = 0
    @State private var muted = RaceAudio.isMuted

    var body: some View {
        ZStack {
            GameView(track: track, state: state, restartToken: restartToken)
                .ignoresSafeArea()
            HUDView(state: state, trackName: track.name)
                .allowsHitTesting(false)
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
                    CircleButton(systemName: "arrow.counterclockwise") { restartToken += 1 }
                    CircleButton(systemName: "house.fill", action: onExit)
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
    }
}

struct CircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct HUDView: View {
    let state: GameState
    let trackName: String

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(state.speedKmh) км/ч")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("\(trackName) · круг \(state.laps)")
                        .font(.system(size: 14, weight: .semibold))
                    Text(formatLapTime(state.currentLapTime))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    if state.lapInvalid {
                        Text("КРУГ НЕ ЗАСЧИТАН")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.orange)
                    } else if let delta = state.delta {
                        // Минус — быстрее лучшего круга (зелёный), плюс — медленнее (красный).
                        Text("\(state.deltaLabel)  \(formatDelta(delta))")
                            .font(.system(size: 18, weight: .heavy, design: .monospaced))
                            .foregroundStyle(delta < 0 ? Color(red: 0.3, green: 0.95, blue: 0.4)
                                             : delta > 0 ? Color(red: 1, green: 0.35, blue: 0.3) : .white)
                    }
                    if let best = state.bestLap {
                        Text("Лучший: \(formatLapTime(best))")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    if state.offTrack {
                        Text("ВНЕ ТРАССЫ")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.yellow)
                    }
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            if state.wrongWay {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 22, weight: .heavy))
                    Text("НЕ ТО НАПРАВЛЕНИЕ")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color(red: 0.86, green: 0.13, blue: 0.13).opacity(0.92), in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .padding(.top, 24)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if let banner = state.banner {
                HStack(spacing: 10) {
                    Image(systemName: state.bannerIcon)
                        .font(.system(size: 20, weight: .heavy))
                    Text(banner.uppercased())
                        .font(.system(size: 20, weight: .black, design: .rounded))
                }
                .foregroundStyle(state.bannerIsGood ? .black : .white)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(state.bannerIsGood ? Color(red: 1, green: 0.8, blue: 0.2) : Color(white: 0.2).opacity(0.9),
                            in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .padding(.top, 12)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            // Подсказка — в верхней части экрана: внизу стоит машина (камера смотрит вперёд) и мини-карта.
            if state.showHint && !state.hasTouched && (state.startLights == nil || state.startLights == .green) {
                Text("Веди пальцем по трассе — машина поедет следом.\nБыстрее палец — быстрее машина.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 24)
            }
            Spacer()
        }
        .padding()
        .overlay {
            ZStack {
                if let lights = state.startLights {
                    StartLightsView(lights: lights)
                        .transition(.opacity)
                }
            }
            .offset(y: -60)
            .animation(.easeOut(duration: 0.3), value: state.startLights)
            .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.25), value: state.wrongWay)
        .animation(.easeOut(duration: 0.25), value: state.banner)
    }
}

/// Стартовые огни: три красных гаснут по очереди, потом все три загораются зелёным.
struct StartLightsView: View {
    let lights: StartLights

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { i in
                let color: Color? = switch lights {
                case .green: Color(red: 0.2, green: 1, blue: 0.35)
                case .red(let lit): i < lit ? Color(red: 1, green: 0.12, blue: 0.1) : nil
                }
                Circle()
                    .fill(color ?? Color(white: 0.18))
                    .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 3))
                    .frame(width: 52, height: 52)
                    .shadow(color: color?.opacity(0.9) ?? .clear, radius: 14)
                    .animation(.easeOut(duration: 0.12), value: lights)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color(white: 0.08).opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }
}

// MARK: - Мини-карта

/// Силуэт трассы для мини-карты. Поворачивается вместе с камерой гонки, поэтому вписывается
/// в квадрат по описанной окружности — при любом повороте карта не вылезает за рамку.
@MainActor
struct Minimap {
    static let size: CGFloat = 130

    let points: [SIMD2<Float>]
    let start: SIMD2<Float>
    /// Границы секторов (те же отсечки, что в LapTimer): точка на осевой и направление трассы.
    let sectorMarks: [(point: SIMD2<Float>, tangent: SIMD2<Float>)]
    private let center: SIMD2<Float>
    private let radius: Float

    private static var cache: [TrackID: Minimap] = [:]

    static func get(_ id: TrackID) -> Minimap {
        if let cached = cache[id] { return cached }
        let map = Minimap(track: Track(TrackDefinition.get(id)))
        cache[id] = map
        return map
    }

    private init(track: Track) {
        let pts = stride(from: 0, to: track.points.count, by: 3).map { track.points[$0] }
        points = pts
        start = track.points[0]
        let n = track.points.count
        sectorMarks = (1..<LapTimer.sectorCount).map { k in
            let i = n * k / LapTimer.sectorCount
            return (track.points[i], track.tangents[i])
        }
        let lo = pts.reduce(pts[0]) { simd_min($0, $1) }, hi = pts.reduce(pts[0]) { simd_max($0, $1) }
        center = (lo + hi) / 2
        radius = pts.map { simd_distance($0, (lo + hi) / 2) }.max()!
    }

    /// Мировая точка (x, z) → точка внутри `rect` с учётом курса камеры: «вверх» на карте — вперёд для камеры.
    func project(_ p: SIMD2<Float>, yaw: Float, in rect: CGRect) -> CGPoint {
        let f = SIMD2(sin(yaw), cos(yaw))
        let d = p - center
        let scale = Float(min(rect.width, rect.height)) / 2 / radius
        return CGPoint(x: rect.midX + CGFloat((-f.y * d.x + f.x * d.y) * scale),
                       y: rect.midY + CGFloat(-(f.x * d.x + f.y * d.y) * scale))
    }
}

struct MinimapView: View {
    let track: TrackDefinition
    let state: GameState

    var body: some View {
        let map = Minimap.get(track.id)
        let car = state.carPosition, yaw = state.cameraYaw
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
            var path = Path()
            if let first = map.points.first {
                path.move(to: map.project(first, yaw: yaw, in: rect))
                for p in map.points.dropFirst() { path.addLine(to: map.project(p, yaw: yaw, in: rect)) }
                path.closeSubpath()
            }
            context.stroke(path, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            // Границы секторов — жёлтые штрихи поперёк трассы.
            for mark in map.sectorMarks {
                let p = map.project(mark.point, yaw: yaw, in: rect)
                let ahead = map.project(mark.point + mark.tangent * 20, yaw: yaw, in: rect)
                let dx = ahead.x - p.x, dy = ahead.y - p.y
                let len = max(hypot(dx, dy), 0.001)
                let nx = -dy / len * 7, ny = dx / len * 7
                var tick = Path()
                tick.move(to: CGPoint(x: p.x - nx, y: p.y - ny))
                tick.addLine(to: CGPoint(x: p.x + nx, y: p.y + ny))
                context.stroke(tick, with: .color(Color(red: 1, green: 0.82, blue: 0.2)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            let start = map.project(map.start, yaw: yaw, in: rect)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(.black))

            // Призрак лучшего круга — полупрозрачная белая точка.
            if let ghost = state.ghostPosition {
                let g = map.project(ghost, yaw: yaw, in: rect)
                context.fill(Path(ellipseIn: CGRect(x: g.x - 5, y: g.y - 5, width: 10, height: 10)),
                             with: .color(.white.opacity(0.55)))
            }

            let dot = map.project(car, yaw: yaw, in: rect)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                         with: .color(Color(red: 0.9, green: 0.12, blue: 0.12)))
        }
        .frame(width: Minimap.size, height: Minimap.size)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}
