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
