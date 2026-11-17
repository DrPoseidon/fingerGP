import AVFoundation
import UIKit
import os

/// Следит, чтобы аудиодвижок работал, пока он нужен.
///
/// Первый `start()` может прийтись на момент, когда приложение ещё не стало активным, — iOS тогда
/// отказывает в запуске звука. Движок также останавливается системой при прерываниях (звонок, Siri)
/// и смене выхода (наушники). Поэтому запуск повторяется: при активации приложения, после прерывания,
/// после смены конфигурации и раз в секунду из игрового цикла (`tick`).
@MainActor
final class AudioKeeper {
    private let engine: AVAudioEngine
    private let name: String
    private var wanted = false
    private var lastAttempt: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private static let log = Logger(subsystem: "com.example.RaceGame", category: "audio")

    init(engine: AVAudioEngine, name: String) {
        self.engine = engine
        self.name = name
        let center = NotificationCenter.default
        let restart: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.ensureRunning(force: true) }
        }
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: restart),
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: restart),
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main, using: restart),
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        wanted = true
        ensureRunning(force: true)
    }

    func stop() {
        wanted = false
        engine.stop()
    }

    /// Вызывать из игрового цикла: не чаще раза в секунду пробует запустить остановившийся движок.
    func tick() {
        ensureRunning(force: false)
    }

    private func ensureRunning(force: Bool) {
        guard wanted, !engine.isRunning else { return }
        let now = CACurrentMediaTime()
        guard force || now - lastAttempt > 1 else { return }
        lastAttempt = now
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try engine.start()
            AudioKeeper.log.info("\(self.name, privacy: .public): audio engine started")
        } catch {
            AudioKeeper.log.error("\(self.name, privacy: .public): audio engine start failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
