import Foundation

/// Отладочные аргументы запуска (`-autopilot`, `-track oval`, `-coins 3000` …) — см. README.
/// Работают только в отладочной сборке: в релизной список пуст, и все проверки возвращают «нет».
enum DebugFlags {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    #else
    private static let arguments: [String] = []
    #endif

    /// Есть ли флаг `name` (например, "-autopilot").
    static func has(_ name: String) -> Bool { arguments.contains(name) }

    /// Значение после флага: `-track oval` → "oval".
    static func value(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static func int(_ name: String) -> Int? { value(name).flatMap(Int.init) }
}
