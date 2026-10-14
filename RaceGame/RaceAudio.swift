import AVFoundation
import UIKit
import simd

/// Звук гонки — синтезируется в реальном времени, без звуковых файлов:
/// мотор (гармоники, плавно растущие со скоростью),
/// рокот поребриков и травы, короткие сигналы круга и рекорда.
///
/// Игровой цикл раз в кадр вызывает `update(...)`; звуковой поток читает параметры и плавно к ним подтягивается.
@MainActor
final class RaceAudio {
    enum Chime: Int { case lap = 1, record = 2, countdown = 3, go = 4 }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let synth = Synth()

    private static let mutedKey = "sound.muted"
    static var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }

    init() {
        // .ambient: звук смешивается с музыкой игрока и выключается переключателем «без звука».
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let output = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let synth = self.synth
        synth.sampleRate = Float(sampleRate)
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(into: data, count: Int(frameCount))
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = RaceAudio.isMuted ? 0 : 1
    }

    private lazy var keeper = AudioKeeper(engine: engine, name: "race")

    func start() { keeper.start() }

    func stop() { keeper.stop() }

    /// Применить настройку «без звука» (её переключает кнопка на экране гонки).
    func syncMute() {
        keeper.tick()
        let volume: Float = RaceAudio.isMuted ? 0 : 1
        if engine.mainMixerNode.outputVolume != volume { engine.mainMixerNode.outputVolume = volume }
    }

    /// - Parameters:
    ///   - speed: м/с; `throttle` — 0…1; `onCurb`/`onGrass` — где сейчас колёса.
    func update(speed: Float, maxSpeed: Float, throttle: Float, onCurb: Bool, onGrass: Bool) {
        synth.targetRPM = RaceAudio.rpm(speed: speed, maxSpeed: maxSpeed)
        synth.targetThrottle = throttle
        synth.targetCurb = onCurb ? min(speed / 15, 1) : 0
        synth.targetGrass = onGrass ? min(speed / 25, 1) : 0
        synth.speed = speed
    }

    func play(_ chime: Chime) {
        synth.chimeKind = chime.rawValue
        synth.chimeRequest &+= 1
    }

    /// «Обороты» 0.2…1 — плавно растут со скоростью, без имитации передач: ровное усиливающееся жужжание.
    /// Степень < 1 — на малых скоростях тон растёт быстрее, на высоких — спокойнее.
    static func rpm(speed: Float, maxSpeed: Float) -> Float {
        0.2 + 0.8 * pow(simd_clamp(speed / maxSpeed, 0, 1), 0.7)
    }
}

/// Синтезатор. Параметры пишет главный поток, читает звуковой: это отдельные Float/Int,
/// рассинхрон на один буфер неважен, а блокировок в звуковом потоке быть не должно.
private final class Synth: @unchecked Sendable {
    var sampleRate: Float = 48_000

    var targetRPM: Float = 0.25
    var targetThrottle: Float = 0
    var targetCurb: Float = 0
    var targetGrass: Float = 0
    var speed: Float = 0
    var chimeRequest = 0
    var chimeKind = 0

    // Сглаженные значения (только звуковой поток).
    private var rpm: Float = 0.25
    private var throttle: Float = 0
    private var curb: Float = 0
    private var grass: Float = 0

    private var enginePhase: Float = 0
    private var curbPhase: Float = 0
    private var noiseSeed: UInt32 = 0x1234_5678
    // Фильтры шума: для шипения шин и для рокота.
    private var grassLP: Float = 0
    private var curbLP: Float = 0
    private var engineLP: Float = 0

    private var seenChime = 0
    private var chimeNotes: (Float, Float, Float) = (0, 0, 0)
    private var chimeNoteCount = 0
    private var chimeSample = 0
    private var chimePhase: Float = 0
    private var chimeNoteSeconds: Float = 0.11

    private func noise() -> Float {
        noiseSeed = noiseSeed &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: noiseSeed)) / Float(Int32.max)
    }

    func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        let sr = sampleRate
        let smooth: Float = 1 - exp(-1 / (0.05 * sr))       // ~50 мс
        let slowSmooth: Float = 1 - exp(-1 / (0.12 * sr))
        let twoPi = 2 * Float.pi

        if chimeRequest != seenChime {
            seenChime = chimeRequest
            // Круг — две ноты вверх, рекорд — три; погасший красный огонь — короткий писк, зелёный — длинный и выше.
            switch chimeKind {
            case 2: chimeNotes = (784, 988, 1319); chimeNoteCount = 3
            case 3: chimeNotes = (880, 0, 0); chimeNoteCount = 1
            case 4: chimeNotes = (1760, 0, 0); chimeNoteCount = 1
            default: chimeNotes = (659, 988, 0); chimeNoteCount = 2
            }
            chimeSample = 0
            chimeNoteSeconds = chimeKind == 4 ? 0.6 : 0.11
        }
        let noteLength = Int(chimeNoteSeconds * sr)

        for i in 0..<count {
            rpm += (targetRPM - rpm) * smooth
            throttle += (targetThrottle - throttle) * slowSmooth
            curb += (targetCurb - curb) * smooth
            grass += (targetGrass - grass) * smooth

            // Мотор: основной тон 70…330 Гц, насыщенный гармониками; под нагрузкой громче и «рычит».
            let freq = 70 + 260 * rpm
            enginePhase += twoPi * freq / sr
            if enginePhase > twoPi * 2 { enginePhase -= twoPi * 2 }
            let p = enginePhase
            var engineSample = 0.5 * sin(p) + 0.32 * sin(2 * p + 0.4) + 0.2 * sin(3 * p + 1.1)
                + 0.12 * sin(4 * p + 0.2) + 0.07 * sin(6 * p)
            engineSample *= 1 + 0.25 * sin(p * 0.5)            // субгармоника — «рокот» цилиндров
            engineLP += (noise() - engineLP) * 0.2
            engineSample += engineLP * 0.25 * throttle
            let engineVolume = 0.08 + 0.12 * throttle + 0.14 * rpm

            // Поребрики: низкий шум, «нарезанный» с частотой смены полос (полоса 1.8 м).
            curbPhase += twoPi * max(speed / 1.8, 1) / sr
            if curbPhase > twoPi { curbPhase -= twoPi }
            curbLP += (noise() - curbLP) * 0.05
            let curbSample = curbLP * (sin(curbPhase) > 0 ? 1 : 0.2) * 1.6 * curb

            // Трава: глухой шорох.
            grassLP += (noise() - grassLP) * 0.03
            let grassSample = grassLP * 1.4 * grass

            // Сигналы круга/рекорда.
            var chimeSample: Float = 0
            if chimeNoteCount > 0 && self.chimeSample < noteLength * chimeNoteCount {
                let note = self.chimeSample / noteLength
                let noteFreq = note == 0 ? chimeNotes.0 : note == 1 ? chimeNotes.1 : chimeNotes.2
                chimePhase += twoPi * noteFreq / sr
                if chimePhase > twoPi { chimePhase -= twoPi }
                let local = Float(self.chimeSample % noteLength) / Float(noteLength)
                let envelope = min(local * 20, 1) * (1 - local)
                chimeSample = (sin(chimePhase) + 0.3 * sin(2 * chimePhase)) * envelope * 0.22
                self.chimeSample += 1
            }

            let mix = engineSample * engineVolume + curbSample + grassSample + chimeSample
            out[i] = tanh(mix * 1.4) * 0.8
        }
    }
}
