import Foundation
import Observation
import UIKit

/// Машина из гаража: та же модель болида, но свои характеристики и размер крыльев.
struct CarModel: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let price: Int
    /// Множители к характеристикам стандартной машины.
    let acceleration: Float
    let topSpeed: Float
    let grip: Float
    /// Масштаб переднего и заднего крыла — внешнее отличие.
    let frontWing: Float
    let rearWing: Float

    static let standard = CarModel(id: "standard", name: "Стандарт", subtitle: "Сбалансированный болид",
                                   price: 0, acceleration: 1, topSpeed: 1, grip: 1, frontWing: 1, rearWing: 1)
    static let all: [CarModel] = [
        standard,
        CarModel(id: "sprinter", name: "Спринтер", subtitle: "Резкий разгон из поворотов",
                 price: 1500, acceleration: 1.15, topSpeed: 0.97, grip: 1, frontWing: 1.1, rearWing: 1.2),
        CarModel(id: "arrow", name: "Стрела", subtitle: "Выше максимальная скорость, тоньше крылья",
                 price: 2500, acceleration: 0.97, topSpeed: 1.07, grip: 0.98, frontWing: 0.85, rearWing: 0.7),
        CarModel(id: "grip", name: "Цепкий", subtitle: "Больше прижимной силы — быстрее в поворотах",
                 price: 4000, acceleration: 1, topSpeed: 0.99, grip: 1.08, frontWing: 1.25, rearWing: 1.35),
    ]

    static func get(_ id: String) -> CarModel { all.first { $0.id == id } ?? standard }
}

/// Ливрея — три цвета модели: основной (кузов, понтоны, шлем — красные детали), второй (бока и крылья —
/// белые детали) и акцент (воздухозаборник, зеркала, закрылки — синие детали).
/// Сочетания цветов — по мотивам узнаваемых гоночных расцветок, но названия свои, без команд и спонсоров.
struct Livery: Identifiable, Equatable {
    let id: String
    let name: String
    let price: Int
    let primary: UIColor
    let secondary: UIColor
    let accent: UIColor

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static let classic = Livery(id: "classic", name: "Классика", price: 0,
                                primary: rgb(0.86, 0.13, 0.11), secondary: rgb(0.94, 0.94, 0.96), accent: rgb(0.16, 0.22, 0.72))
    static let all: [Livery] = [
        classic,
        // Чёрный, тёмное серебро и бирюза.
        Livery(id: "night", name: "Полночь", price: 300,
               primary: rgb(0.08, 0.08, 0.1), secondary: rgb(0.55, 0.57, 0.6), accent: rgb(0.0, 0.75, 0.68)),
        // Оранжевая папайя, карбон и электрик.
        Livery(id: "papaya", name: "Папайя", price: 300,
               primary: rgb(1, 0.5, 0.0), secondary: rgb(0.1, 0.1, 0.12), accent: rgb(0.1, 0.55, 1)),
        // Тёмно-синий, красный и жёлтый.
        Livery(id: "dusk", name: "Сумерки", price: 400,
               primary: rgb(0.1, 0.14, 0.35), secondary: rgb(0.85, 0.1, 0.15), accent: rgb(1, 0.82, 0.05)),
        // Британский зелёный, графит и лайм.
        Livery(id: "emerald", name: "Изумруд", price: 500,
               primary: rgb(0.0, 0.36, 0.25), secondary: rgb(0.15, 0.16, 0.17), accent: rgb(0.75, 0.95, 0.1)),
        // Яркий синий, чёрный и розовый.
        Livery(id: "electro", name: "Электро", price: 600,
               primary: rgb(0.0, 0.45, 0.95), secondary: rgb(0.06, 0.07, 0.12), accent: rgb(1, 0.35, 0.7)),
        // Голубой, тёмно-синий и белый.
        Livery(id: "ocean", name: "Океан", price: 700,
               primary: rgb(0.0, 0.55, 0.9), secondary: rgb(0.05, 0.12, 0.3), accent: rgb(0.95, 0.95, 0.97)),
        // Белый, синий и красный.
        Livery(id: "snow", name: "Снег", price: 800,
               primary: rgb(0.95, 0.95, 0.97), secondary: rgb(0.12, 0.2, 0.6), accent: rgb(0.86, 0.1, 0.15)),
        // Белый, чёрный и красный.
        Livery(id: "contrast", name: "Контраст", price: 900,
               primary: rgb(0.95, 0.95, 0.97), secondary: rgb(0.08, 0.08, 0.1), accent: rgb(0.86, 0.1, 0.12)),
        // Титан, чёрный и красный.
        Livery(id: "titan", name: "Титан", price: 1000,
               primary: rgb(0.62, 0.63, 0.65), secondary: rgb(0.07, 0.07, 0.08), accent: rgb(0.9, 0.08, 0.12)),
        // Белый, чёрный и золото.
        Livery(id: "champagne", name: "Шампань", price: 1200,
               primary: rgb(0.96, 0.96, 0.95), secondary: rgb(0.08, 0.08, 0.09), accent: rgb(0.85, 0.68, 0.3)),
    ]

    static func get(_ id: String) -> Livery { all.first { $0.id == id } ?? classic }
}

/// Кошелёк игрока: монеты, купленные машины и ливреи, выбранные машина и ливрея.
@MainActor
@Observable
final class Wallet {
    static let shared = Wallet()

    private let defaults = UserDefaults.standard
    private(set) var coins: Int
    private(set) var owned: Set<String>
    var selectedCar: String { didSet { defaults.set(selectedCar, forKey: "wallet.car") } }
    var selectedLivery: String { didSet { defaults.set(selectedLivery, forKey: "wallet.livery") } }

    private init() {
        // Для отладки: `-coins N` — задать баланс.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-coins"), i + 1 < args.count, let n = Int(args[i + 1]) {
            defaults.set(n, forKey: "wallet.coins")
        }
        coins = defaults.integer(forKey: "wallet.coins")
        owned = Set(defaults.stringArray(forKey: "wallet.owned") ?? [])
        selectedCar = defaults.string(forKey: "wallet.car") ?? CarModel.standard.id
        selectedLivery = defaults.string(forKey: "wallet.livery") ?? Livery.classic.id
    }

    var car: CarModel { CarModel.get(selectedCar) }
    var livery: Livery { Livery.get(selectedLivery) }

    func earn(_ amount: Int) {
        guard amount > 0 else { return }
        coins += amount
        defaults.set(coins, forKey: "wallet.coins")
    }

    func owns(car: CarModel) -> Bool { car.price == 0 || owned.contains("car.\(car.id)") }
    func owns(livery: Livery) -> Bool { livery.price == 0 || owned.contains("livery.\(livery.id)") }

    /// Купить и сразу выбрать. false — не хватает монет.
    @discardableResult
    func buy(car: CarModel) -> Bool {
        guard owns(car: car) || spend(car.price, item: "car.\(car.id)") else { return false }
        selectedCar = car.id
        return true
    }

    @discardableResult
    func buy(livery: Livery) -> Bool {
        guard owns(livery: livery) || spend(livery.price, item: "livery.\(livery.id)") else { return false }
        selectedLivery = livery.id
        return true
    }

    private func spend(_ price: Int, item: String) -> Bool {
        guard coins >= price else { return false }
        coins -= price
        owned.insert(item)
        defaults.set(coins, forKey: "wallet.coins")
        defaults.set(Array(owned), forKey: "wallet.owned")
        return true
    }
}

/// Сколько монет за что.
@MainActor
enum Rewards {
    private static let defaults = UserDefaults.standard

    /// Тренировка: за улучшение своего рекорда.
    static let record = 25

    /// Новая медаль на трассе: за каждую ступень — один раз (сразу на золото — за все три).
    static func medal(_ medal: Medal?, on id: TrackID) -> Int {
        guard let medal else { return 0 }
        let key = "reward.medal.\(id.rawValue)"
        let rewarded = defaults.integer(forKey: key)
        guard medal.rawValue > rewarded else { return 0 }
        defaults.set(medal.rawValue, forKey: key)
        let prices = [Medal.bronze: 50, .silver: 100, .gold: 200]
        return Medal.allCases.filter { $0.rawValue > rewarded && $0 <= medal }.reduce(0) { $0 + prices[$1]! }
    }

    /// Гонка: за место, с поправкой на длину гонки; первая победа на трассе — бонус.
    static func race(place: Int, on id: TrackID) -> Int {
        let base = [150, 100, 60, 30][min(max(place, 1), 4) - 1]
        let factor: Double
        switch id {
        case .oval: factor = 0.8
        case .harbor: factor = 1
        case .pass: factor = 1.2
        case .forest: factor = 1.5
        }
        var total = Int((Double(base) * factor).rounded())
        let winKey = "reward.firstWin.\(id.rawValue)"
        if place == 1 && !defaults.bool(forKey: winKey) {
            defaults.set(true, forKey: winKey)
            total += 100
        }
        return total
    }
}
