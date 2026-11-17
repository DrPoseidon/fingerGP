import SwiftUI
import simd

@main
struct RaceGameApp: App {
    init() {
        LapRecords.dropLegacyRecords()
        LapRecords.dropRemovedTracks()
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
    case menu, modeSelect, trackSelect
    case race(TrackID, GameMode)
}

struct RootView: View {
    @State private var screen: Screen = Screen.initial
    /// Режим, выбранный на экране режимов, — с ним открывается выбранная трасса.
    @State private var mode: GameMode = ProcessInfo.processInfo.arguments.contains("-race") ? .race : .training

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
                        onSelect: { selected in
                            mode = selected
                            withAnimation(.easeInOut(duration: 0.3)) { screen = .trackSelect }
                        })
                        .transition(.opacity)
                } else {
                    TrackSelectView(
                        onBack: { withAnimation(.easeInOut(duration: 0.3)) { screen = .modeSelect } },
                        onSelect: { screen = .race($0, mode) })
                        .transition(.opacity)
                }
            case .race(let id, let mode):
                RaceView(track: TrackDefinition.get(id), mode: mode) { screen = .menu }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

extension Screen {
    /// Для отладки: `-autopilot` или `-track <id>` сразу открывают заезд (по умолчанию — Гавань),
    /// `-race` — в режиме гонки, `-screen select` — экран выбора трассы.
    static var initial: Screen {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-screen"), i + 1 < args.count {
            if args[i + 1] == "select" { return .trackSelect }
            if args[i + 1] == "mode" { return .modeSelect }
        }
        guard args.contains("-autopilot") || args.contains("-track") else { return .menu }
        let mode: GameMode = args.contains("-race") ? .race : .training
        if let i = args.firstIndex(of: "-track"), i + 1 < args.count, let id = TrackID(rawValue: args[i + 1]) {
            return .race(id, mode)
        }
        return .race(.harbor, mode)
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
                    if let place = LapRecords.racePlace(def.id) {
                        RaceTrophy(place: place)
                    }
                    MedalIcon(medal: MedalStore.shared.earned(on: def.id), size: 16)
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

            Toggle(isOn: $collisions) {
                Text("Столкновения в гонке")
                    .font(.system(size: 17, weight: .bold))
            }
            .tint(Color(red: 0.86, green: 0.13, blue: 0.13))

            Toggle(isOn: $showFPS) {
                Text("Показывать FPS")
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
    let onSelect: (GameMode) -> Void

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
            Button { onSelect(.training) } label: {
                ModeCard(icon: "stopwatch", title: "Тренировка",
                         subtitle: "Свободные круги в одиночку — оттачивай траекторию и ставь рекорды")
            }
            .buttonStyle(.plain)
            Button { onSelect(.race) } label: {
                ModeCard(icon: "flag.checkered", title: "Гонка",
                         subtitle: "Старт с последнего места против трёх соперников — обгони всех за несколько кругов",
                         color: Color(red: 0.16, green: 0.42, blue: 0.95))
            }
            .buttonStyle(.plain)
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
    var color = Color(red: 0.86, green: 0.13, blue: 0.13)
    var locked = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 64, height: 64)
                .background(locked ? Color.white.opacity(0.12) : color,
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
                        let unlocked = MedalStore.shared.isUnlocked(def.id)
                        Button { onSelect(def.id) } label: { TrackCard(definition: def, unlocked: unlocked) }
                            .buttonStyle(.plain)
                            .disabled(!unlocked)
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
    var unlocked = true

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
                let store = MedalStore.shared
                if unlocked {
                    // Медальные времена: полученные — яркие, остальные — приглушённые.
                    let earned = store.earned(on: definition.id)
                    HStack(spacing: 8) {
                        ForEach(Medal.allCases) { medal in
                            if let time = store.time(medal, on: definition.id) {
                                let got = earned.map { medal <= $0 } ?? false
                                HStack(spacing: 3) {
                                    Image(systemName: "medal.fill").foregroundStyle(Color(medal.color))
                                    Text(formatLapTime(time))
                                }
                                .opacity(got ? 1 : 0.45)
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
                } else {
                    // Очки медалей: бронза — 1, серебро — 2, золото — 3.
                    Label("Медали: \(store.points)/\(MedalStore.requiredPoints(definition.id)) — бронза 1, серебро 2, золото 3",
                          systemImage: "medal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(Medal.gold.color))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            Image(systemName: unlocked ? "chevron.right" : "lock.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .opacity(unlocked ? 1 : 0.6)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }
}

/// Значок медали: цветной кружок с медалью; nil — пустой контур (медали ещё нет).
struct MedalIcon: View {
    let medal: Medal?
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: medal == nil ? "circle.dashed" : "medal.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(medal.map { Color($0.color) } ?? .white.opacity(0.35))
    }
}

/// Лучшее место в гонке: кубок с номером места.
struct RaceTrophy: View {
    let place: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "trophy.fill")
            Text("\(place)")
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(place == 1 ? Color(red: 1, green: 0.8, blue: 0.2) : .white.opacity(0.75))
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
    let mode: GameMode
    let onExit: () -> Void
    @State private var state = GameState()
    @State private var restartToken = 0
    @State private var muted = RaceAudio.isMuted

    var body: some View {
        ZStack {
            GameView(track: track, mode: mode, state: state, restartToken: restartToken)
                .ignoresSafeArea()
            HUDView(state: state, trackName: track.name)
                .allowsHitTesting(false)
            if state.showGestureHint {
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
        .overlay {
            if let results = state.raceResults {
                RaceResultsView(results: results, bestLap: state.bestLap,
                                onRestart: { restartToken += 1 }, onExit: onExit)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: state.showGestureHint)
        .animation(.easeOut(duration: 0.4), value: state.raceResults)
    }
}

/// Итоги гонки: места, время победителя и отставания остальных.
struct RaceResultsView: View {
    let results: [RaceResult]
    let bestLap: Double?
    let onRestart: () -> Void
    let onExit: () -> Void

    var body: some View {
        let place = results.first(where: \.isPlayer)?.position ?? results.count
        let leader = results.first?.time ?? 0
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Image(systemName: place == 1 ? "trophy.fill" : "flag.checkered")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(place == 1 ? Color(red: 1, green: 0.8, blue: 0.2) : .white)
                    Text(place == 1 ? "Победа!" : "Финиш · \(place)-е место")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                }
                VStack(spacing: 8) {
                    ForEach(results) { r in
                        HStack(spacing: 12) {
                            Text("\(r.position)")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .frame(width: 22)
                            Circle().fill(Color(r.color)).frame(width: 14, height: 14)
                            Text(r.name)
                                .font(.system(size: 17, weight: r.isPlayer ? .heavy : .semibold))
                            Spacer()
                            Text(r.position == 1 ? formatLapTime(r.time) : "+" + String(format: "%.2f", r.time - leader))
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(r.isPlayer ? Color.white.opacity(0.18) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if let bestLap {
                    Text("Лучший круг: \(formatLapTime(bestLap))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .opacity(0.8)
                }
                HStack(spacing: 12) {
                    Button(action: onExit) {
                        Text("В меню")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                    Button(action: onRestart) {
                        Text("Ещё раз")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color(red: 0.86, green: 0.13, blue: 0.13), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(22)
            .background(Color(white: 0.1).opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 20)
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
                    if state.mode == .race {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(state.racePosition)/\(RaceSession.carCount)")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.2))
                            Text("\(state.speedKmh) км/ч")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                        }
                        Text("\(trackName) · круг \(state.raceLap)/\(state.lapsTotal)")
                            .font(.system(size: 14, weight: .semibold))
                        Text(formatLapTime(state.raceTime))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        if state.draft > 0.3 {
                            Label("Слипстрим", systemImage: "wind")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 1))
                        }
                    } else {
                        Text("\(state.speedKmh) км/ч")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Text("\(trackName) · круг \(state.laps)")
                            .font(.system(size: 14, weight: .semibold))
                        Text(formatLapTime(state.currentLapTime))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
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
                    if let target = state.medalTarget {
                        HStack(spacing: 5) {
                            MedalIcon(medal: target.medal, size: 13)
                            Text("Цель: \(formatLapTime(target.time))")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
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
            if let fps = state.fps {
                // Самый долгий кадр больше ~25 мс — заметное подёргивание.
                Text(String(format: "%.0f FPS · макс. кадр %.0f мс", fps.average, fps.worstMs))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(fps.average < 55 || fps.worstMs > 25 ? .orange : .white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
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

/// Подсказка жестом, когда машина долго стоит: палец касается экрана над машиной (расходится круг)
/// и ведёт вверх, оставляя след. Повторяется по кругу.
struct GestureHintView: View {
    /// Путь пальца на экране (точки трассы впереди машины); пустой — по центру, снизу вверх.
    let path: [CGPoint]
    private static let cycle = 2.7
    // Фазы цикла, с: появление, нажатие, ведение, исчезновение, дальше пауза.
    private static let pressAt = 0.3
    private static let moveAt = 0.55
    private static let moveDuration = 1.1
    /// Цикл отсчитывается от появления подсказки — первый показ начинается с касания, а не с середины.
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.cycle)
                let moveEnd = Self.moveAt + Self.moveDuration
                let appear = min(max(t / Self.pressAt, 0), 1)
                let press = min(max((t - Self.pressAt) / 0.15, 0), 1)
                let move = smoothstep((t - Self.moveAt) / Self.moveDuration)
                let fade = 1 - min(max((t - moveEnd) / 0.4, 0), 1)
                let ripple = min(max((t - Self.pressAt) / 0.6, 0), 1)
                let points = path.count >= 2 ? path : [
                    CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.62),
                    CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.62 - 170),
                ]
                let trail = prefix(of: points, fraction: move)
                let tip = trail.last ?? points[0]

                ZStack {
                    // След пальца — по пройденной части пути.
                    Path { p in p.addLines(trail) }
                        .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    // Круг от касания.
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 26 + 50 * ripple, height: 26 + 50 * ripple)
                        .opacity((1 - ripple) * (press > 0 ? 1 : 0))
                        .position(points[0])
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 22, height: 22)
                        .opacity(press)
                        .position(tip)
                    // Рука: кончик указательного пальца — в точке касания.
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                        .scaleEffect(1 - 0.12 * press, anchor: .topLeading)
                        .position(x: tip.x + 26, y: tip.y + 34)
                }
                .opacity(appear * fade)
            }
        }
        .ignoresSafeArea()
        .task { await playHaptics() }
    }

    /// Вибрация в такт анимации: короткий щелчок на касании, непрерывная — пока палец ведёт.
    private func playHaptics() async {
        let haptics = HintHaptics()
        var cycleStart = start
        func wait(until offset: Double) async {
            let delay = cycleStart.addingTimeInterval(offset).timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        }
        while !Task.isCancelled {
            await wait(until: Self.pressAt)
            if Task.isCancelled { break }
            haptics.tap()
            await wait(until: Self.moveAt)
            if Task.isCancelled { break }
            haptics.swipe(duration: Self.moveDuration)
            cycleStart = cycleStart.addingTimeInterval(Self.cycle)
            await wait(until: 0)
        }
    }

    /// Начальная часть ломаной длиной `fraction` от всей длины.
    private func prefix(of points: [CGPoint], fraction: Double) -> [CGPoint] {
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var remaining = lengths.reduce(0, +) * fraction
        var out = [points[0]]
        for (i, len) in lengths.enumerated() {
            if remaining >= len {
                out.append(points[i + 1])
                remaining -= len
            } else {
                let k = len > 0 ? remaining / len : 0
                out.append(CGPoint(x: points[i].x + (points[i + 1].x - points[i].x) * k,
                                   y: points[i].y + (points[i + 1].y - points[i].y) * k))
                break
            }
        }
        return out
    }

    private func smoothstep(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
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

            // Призрак медали-цели — точка цвета медали.
            if let medalGhost = state.medalGhostPosition, let medal = state.medalTarget?.medal {
                let g = map.project(medalGhost, yaw: yaw, in: rect)
                context.fill(Path(ellipseIn: CGRect(x: g.x - 5, y: g.y - 5, width: 10, height: 10)),
                             with: .color(Color(medal.color).opacity(0.8)))
            }

            // Соперники — точки своих цветов.
            for o in state.opponents {
                let p = map.project(o.position, yaw: yaw, in: rect)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(Color(o.color)))
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
