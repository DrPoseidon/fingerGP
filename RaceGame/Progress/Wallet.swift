import Foundation
import Observation
import UIKit

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
