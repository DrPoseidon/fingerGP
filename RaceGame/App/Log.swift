import os
import Foundation

/// Журналы приложения (видны в Console.app). Подсистема — ID приложения.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "FingerGP"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let laps = Logger(subsystem: subsystem, category: "laps")
    static let race = Logger(subsystem: subsystem, category: "race")
    static let audio = Logger(subsystem: subsystem, category: "audio")
}
