import AVFoundation

/// Фоновая мелодия меню — мягкий «лаунж» в духе меню Wii/3DS, синтезируется в реальном времени:
/// электропиано (FM, как Rhodes) играет септаккорды, вибрафон — мелодию, круглый бас и тихий шейкер,
/// свинговые восьмые, лёгкая реверберация. Мелодия своя, 8 тактов по кругу.
@MainActor
final class MenuMusic {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private let player = Player()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let output = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48_000
        // Стерео: ревербератор на устройствах не принимает моно (ошибка -10868 при запуске движка).
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let player = self.player
        player.sampleRate = Float(sampleRate)
        Player.warmUp()
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let count = Int(frameCount)
            player.render(into: data, count: count)
            // Тот же сигнал во второй канал (формат неинтерливный — у каждого канала свой буфер).
            for channel in buffers.dropFirst() {
                channel.mData?.assumingMemoryBound(to: Float.self).update(from: data, count: count)
            }
            return noErr
        }
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 22
        engine.attach(node)
        engine.attach(reverb)
        engine.connect(node, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        syncMute()
    }

    private lazy var keeper = AudioKeeper(engine: engine, name: "menu")

    func start() { keeper.start() }

    func stop() { keeper.stop() }

    /// Общая настройка «без звука» с гонкой.
    func syncMute() {
        keeper.tick()
        let volume: Float = RaceAudio.isMuted ? 0 : 1
        if engine.mainMixerNode.outputVolume != volume { engine.mainMixerNode.outputVolume = volume }
    }
}

/// Секвенсор и инструменты. Работает целиком в звуковом потоке, без выделения памяти.
private final class Player: @unchecked Sendable {
    var sampleRate: Float = 48_000

    // MARK: Партитура (MIDI-ноты). Такт = 8 свинговых восьмых. -1 — пауза, -2 — продолжение ноты.
    private static let tempo: Float = 112
    private static let chords: [[Int]] = [
        [60, 64, 67, 71],   // Cmaj7
        [57, 60, 64, 67],   // Am7
        [62, 65, 69, 72],   // Dm7
        [59, 62, 65, 67],   // G7
        [59, 62, 64, 67],   // Em7
        [61, 64, 67, 69],   // A7
        [62, 65, 69, 72],   // Dm7
        [59, 62, 65, 67],   // G7
    ]
    private static let bassRoots = [48, 45, 50, 43, 52, 45, 50, 43]
    private static let melody: [Int] = [
        76, -2, 79, 83, -2, 81, 79, 76,
        84, -2, 83, 81, -2, 76, 79, -2,
        77, 81, 84, -2, 88, -2, 86, 84,
        83, -2, 79, -2, 77, 74, 71, -2,
        79, -2, 83, 86, -2, 83, 79, 76,
        85, -2, 88, -2, 79, -2, 81, 85,
        86, 84, 81, 77, -2, 81, 84, -2,
        83, -2, -2, -2, -1, -1, -1, -1,
    ]
    /// Электропиано: на каких восьмых такта бьёт аккорд (босса-ритм).
    private static let compSteps: Set<Int> = [1, 4, 6]

    // MARK: Состояние секвенсора
    private var sampleInStep = 0
    private var step = -1
    private var fadeIn: Float = 0

    // MARK: Голоса
    private struct Voice {
        var freq: Float = 0
        var phase: Float = 0
        var modPhase: Float = 0
        var age: Float = 10      // секунды с начала ноты
        var level: Float = 0
    }
    private var lead = Voice()
    private var keys = [Voice](repeating: Voice(), count: 4)
    private var bass = Voice()
    private var shakerAge: Float = 10
    private var shakerLevel: Float = 0
    private var hp: Float = 0
    private var seed: UInt32 = 0xC0FFEE
    private var tremolo: Float = 0

    private func noise() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: seed)) / Float(Int32.max)
    }

    /// Инициализировать статические таблицы заранее, в главном потоке, а не в звуковом.
    static func warmUp() {
        _ = chords.count + bassRoots.count + melody.count + compSteps.count
    }

    private static func hz(_ midi: Int) -> Float { 440 * pow(2, Float(midi - 69) / 12) }

    /// Длина восьмой с учётом свинга: первая восьмая доли длиннее (2:1).
    private func stepLength(_ step: Int) -> Int {
        let beat = sampleRate * 60 / Player.tempo
        return Int(beat * (step % 2 == 0 ? 2.0 / 3 : 1.0 / 3))
    }

    private func advance() {
        step = (step + 1) % 64
        let bar = step / 8, inBar = step % 8

        // Мелодия.
        let note = Player.melody[step]
        if note >= 0 {
            lead = Voice(freq: Player.hz(note), age: 0, level: 0.32)
        } else if note == -1 {
            lead.level *= 0.3
        }

        // Аккорды электропиано.
        if Player.compSteps.contains(inBar) {
            let chord = Player.chords[bar]
            for i in 0..<4 {
                keys[i] = Voice(freq: Player.hz(chord[i]), age: 0, level: inBar == 1 ? 0.15 : 0.11)
            }
        }

        // Бас: тоника на «раз», повтор на «два-и», квинта на «три», проходящая на «четыре-и».
        let root = Player.bassRoots[bar]
        switch inBar {
        case 0: bass = Voice(freq: Player.hz(root), age: 0, level: 0.5)
        case 3: bass = Voice(freq: Player.hz(root), age: 0, level: 0.35)
        case 4: bass = Voice(freq: Player.hz(root + 7), age: 0, level: 0.42)
        case 7: bass = Voice(freq: Player.hz(Player.bassRoots[(bar + 1) % 8] - 1), age: 0, level: 0.3)
        default: break
        }

        // Шейкер на каждую восьмую, слабые доли тише.
        shakerAge = 0
        shakerLevel = inBar % 2 == 1 ? 0.06 : 0.035
    }

    func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        let sr = sampleRate
        let dt = 1 / sr
        let twoPi = 2 * Float.pi

        for i in 0..<count {
            if step < 0 || sampleInStep >= stepLength(step) {
                sampleInStep = 0
                advance()
            }
            sampleInStep += 1
            fadeIn = min(fadeIn + dt / 2, 1)

            // Вибрафон: синус + быстро гаснущий 4-й обертон («удар»), лёгкое тремоло мотора.
            tremolo += twoPi * 4.5 * dt
            if tremolo > twoPi { tremolo -= twoPi }
            lead.phase += twoPi * lead.freq * dt
            if lead.phase > twoPi { lead.phase -= twoPi }
            lead.age += dt
            let leadEnv = min(lead.age / 0.004, 1) * exp(-lead.age * 1.6)
            let leadSample = (sin(lead.phase) + 0.3 * sin(4 * lead.phase) * exp(-lead.age * 9))
                * leadEnv * lead.level * (1 + 0.12 * sin(tremolo))

            // Электропиано: FM 1:1 с гаснущим индексом — «колокольчатая» атака, мягкий хвост.
            var keysSample: Float = 0
            for k in 0..<4 {
                keys[k].phase += twoPi * keys[k].freq * dt
                if keys[k].phase > twoPi { keys[k].phase -= twoPi }
                keys[k].modPhase += twoPi * keys[k].freq * dt
                if keys[k].modPhase > twoPi { keys[k].modPhase -= twoPi }
                keys[k].age += dt
                let index = 1.3 * exp(-keys[k].age * 7)
                let env = min(keys[k].age / 0.003, 1) * exp(-keys[k].age * 2.4)
                keysSample += sin(keys[k].phase + index * sin(keys[k].modPhase)) * env * keys[k].level
            }

            // Бас: синус с лёгким вторым обертоном, щипок.
            bass.phase += twoPi * bass.freq * dt
            if bass.phase > twoPi { bass.phase -= twoPi }
            bass.age += dt
            let bassEnv = min(bass.age / 0.005, 1) * exp(-bass.age * 3.2)
            let bassSample = (sin(bass.phase) + 0.25 * sin(2 * bass.phase)) * bassEnv * bass.level

            // Шейкер: высокочастотный шум с очень короткой огибающей.
            let n = noise()
            hp += (n - hp) * 0.3
            shakerAge += dt
            let shakerSample = (n - hp) * exp(-shakerAge * 55) * shakerLevel

            let mix = (leadSample + keysSample + bassSample + shakerSample) * 0.32 * fadeIn
            out[i] = tanh(mix * 1.2)
        }
    }
}
