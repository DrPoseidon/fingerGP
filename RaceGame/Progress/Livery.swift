import Foundation
import Observation
import UIKit

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
