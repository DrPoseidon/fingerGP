import AVFoundation
import UIKit
import simd

/// Звук гонки — синтезируется в реальном времени, без звуковых файлов:
/// мотор (гармоники, плавно растущие со скоростью), визг шин (непрерывный тон с обертонами и шумом трения),
/// рокот поребриков и травы, короткие сигналы круга и рекорда.
///
/// Игровой цикл раз в кадр вызывает `update(...)`; звуковой поток читает параметры и плавно к ним подтягивается.
@MainActor
final class RaceAudio {
    enum Chime: Int { case lap = 1, record = 2 }

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
    ///   - speed: м/с; `throttle`, `squeal` — 0…1; `onCurb`/`onGrass` — где сейчас колёса.
    func update(speed: Float, maxSpeed: Float, throttle: Float, squeal: Float, onCurb: Bool, onGrass: Bool) {
        synth.targetRPM = RaceAudio.rpm(speed: speed, maxSpeed: maxSpeed)
        synth.targetThrottle = throttle
        synth.targetSqueal = squeal
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
    var targetSqueal: Float = 0
    var targetCurb: Float = 0
    var targetGrass: Float = 0
    var speed: Float = 0
    var chimeRequest = 0
    var chimeKind = 0

    // Сглаженные значения (только звуковой поток).
    private var rpm: Float = 0.25
    private var throttle: Float = 0
    private var squeal: Float = 0
    private var curb: Float = 0
    private var grass: Float = 0

    private var enginePhase: Float = 0
    private var curbPhase: Float = 0
    private var noiseSeed: UInt32 = 0x1234_5678
    // Фильтры шума: для шипения шин и для рокота.
    private var squealPhase: Float = 0, squealWobblePhase: Float = 0
    private var squealDrift: Float = 0, squealJitter: Float = 0, hissLowCut: Float = 0
    private var resLow: [Float] = [0, 0, 0, 0], resBand: [Float] = [0, 0, 0, 0]
    /// Основной тон визга шин, Гц (в записи-образце ~1.6 кГц, по просьбе — выше).
    var squealPitch: Float = 2800
    private var grassLP: Float = 0
    private var curbLP: Float = 0
    private var engineLP: Float = 0

    private var seenChime = 0
    private var chimeNotes: (Float, Float, Float) = (0, 0, 0)
    private var chimeNoteCount = 0
    private var chimeSample = 0
    private var chimePhase: Float = 0

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
            // Круг — две ноты вверх, рекорд — три.
            chimeNotes = chimeKind == 2 ? (784, 988, 1319) : (659, 988, 0)
            chimeNoteCount = chimeKind == 2 ? 3 : 2
            chimeSample = 0
        }
        let noteLength = Int(0.11 * sr)

        for i in 0..<count {
            rpm += (targetRPM - rpm) * smooth
            throttle += (targetThrottle - throttle) * slowSmooth
            squeal += (targetSqueal - squeal) * slowSmooth
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

            // Визг шин — по образцу записи пробуксовки: непрерывный тон ~1.6 кГц с обертонами
            // (~3.2 и ~4.8 кГц, третий ярче второго), высота беспорядочно плавает и быстро дрожит (тон размыт в полосу шириной ~100 Гц),
            // поверх — широкий шум трения. Громкость и чуть высота растут с силой заноса.
            squealWobblePhase += twoPi * (2.3 + 0.8 * squealDrift) / sr
            if squealWobblePhase > twoPi { squealWobblePhase -= twoPi }
            squealDrift += (noise() - squealDrift) * 0.0004            // медленный случайный дрейф
            squealJitter += (noise() - squealJitter) * 0.03             // быстрое дрожание — «размывает» тон в полосу
            let pitch = squealPitch * (1 + 0.04 * squeal)
                * (1 + 0.006 * sin(squealWobblePhase) + 0.03 * squealDrift + 0.035 * squealJitter)
            squealPhase += twoPi * pitch / sr
            if squealPhase > twoPi * 2 { squealPhase -= twoPi * 2 }
            let q = squealPhase
            // Тон «размыт» в полосы, как в записи: основной — синус плюс резонатор, обертоны — резонаторы
            // (шум через узкие полосовые фильтры на 2f, 3f, 4f шириной ~100–200 Гц).
            let excitation = noise()
            func resonate(_ i: Int, _ freq: Float, _ damping: Float) -> Float {
                let f = 2 * sin(Float.pi * min(freq, sr * 0.22) / sr)
                resLow[i] += f * resBand[i]
                resBand[i] += f * (excitation - resLow[i] - damping * resBand[i])
                return resBand[i]
            }
            let tone = 1.0 * sin(q)
                + 0.35 * resonate(0, pitch, 0.025)
                + 0.3 * resonate(1, pitch * 2.02, 0.02)
                + 0.4 * resonate(2, pitch * 2.95, 0.018)
                + 0.12 * resonate(3, pitch * 3.95, 0.016)
            let raw = noise()
            hissLowCut += (raw - hissLowCut) * 0.13                    // шум трения: всё ниже ~1 кГц вычитаем
            let hiss = raw - hissLowCut
            let squealSample = (tone * 0.065 + hiss * 0.13) * (0.9 + 0.1 * squealJitter) * squeal

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

            let mix = engineSample * engineVolume + squealSample + curbSample + grassSample + chimeSample
            out[i] = tanh(mix * 1.4) * 0.8
        }
    }
}
