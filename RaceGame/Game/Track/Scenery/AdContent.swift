import RealityKit
import UIKit

/// Формат рекламного места: пропорции картинки.
enum AdFormat: String {
    /// Щит на опорах у трассы.
    case board
    /// Перекладина арки над стартовой прямой.
    case arch
    /// Логотип на траве у поворота.
    case ground

    var pixelSize: CGSize {
        switch self {
        case .board: CGSize(width: 768, height: 256)
        case .arch: CGSize(width: 1024, height: 160)
        case .ground: CGSize(width: 768, height: 256)
        }
    }
}

/// Рекламное место на трассе. `id` стабилен между запусками (трасса, формат, номер) —
/// по нему в будущем можно выдавать конкретную рекламу.
struct AdSlot: Hashable {
    let id: String
    let format: AdFormat
    let index: Int
}

/// Что показывать на рекламном месте. Сейчас — абстрактные заглушки вымышленных «брендов»,
/// нарисованные в коде. Чтобы показывать настоящую рекламу, достаточно заменить `creative(for:)`
/// (например, отдавать картинку, загруженную с сервера), — сцена трассы от этого не меняется.
@MainActor
enum AdContent {
    struct Creative {
        /// Ключ кэша: одинаковые креативы делят текстуру и материал.
        let id: String
        let material: RealityKit.Material
    }

    static func creative(for slot: AdSlot) -> Creative {
        let brand = placeholderBrands[(slot.index + slot.id.utf8.count) % placeholderBrands.count]
        let id = "ad.\(slot.format.rawValue).\(brand.name)"
        if let cached = cache[id] { return cached }
        let image = drawPlaceholder(brand, format: slot.format)
        let creative = Creative(id: id, material: material(from: image, lit: slot.format == .ground))
        cache[id] = creative
        return creative
    }

    /// Табличка расстояния до поворота: белая, с чёрными цифрами.
    static func distanceMarker(_ meters: Int) -> Creative {
        let id = "marker.\(meters)"
        if let cached = cache[id] { return cached }
        let size = CGSize(width: 192, height: 128)
        let image = UIGraphicsImageRenderer(size: size, format: rendererFormat).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.1, alpha: 1).setStroke()
            ctx.cgContext.setLineWidth(10)
            ctx.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
            drawCentered("\(meters)", in: CGRect(origin: .zero, size: size),
                         font: .systemFont(ofSize: 84, weight: .black), color: UIColor(white: 0.1, alpha: 1))
        }
        let creative = Creative(id: id, material: material(from: image, lit: false))
        cache[id] = creative
        return creative
    }

    // MARK: - Заглушки

    private struct Brand {
        let name: String
        let background: UIColor
        let foreground: UIColor
        let accent: UIColor
        let logo: Logo
    }

    private enum Logo { case ring, triangle, chevrons, diamond, bars, dot }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Вымышленные названия и абстрактные знаки — без сходства с реальными марками.
    private static let placeholderBrands: [Brand] = [
        Brand(name: "VELTRA", background: rgb(0.08, 0.1, 0.2), foreground: .white, accent: rgb(0.2, 0.85, 0.95), logo: .ring),
        Brand(name: "KORVEX", background: rgb(0.95, 0.75, 0.1), foreground: rgb(0.1, 0.1, 0.1), accent: rgb(0.85, 0.15, 0.1), logo: .triangle),
        Brand(name: "ZYNTH", background: rgb(0.85, 0.12, 0.15), foreground: .white, accent: rgb(1, 0.85, 0.3), logo: .chevrons),
        Brand(name: "ORBIQ", background: .white, foreground: rgb(0.1, 0.2, 0.55), accent: rgb(0.95, 0.45, 0.1), logo: .dot),
        Brand(name: "MAVERO", background: rgb(0.1, 0.45, 0.25), foreground: .white, accent: rgb(0.75, 0.95, 0.3), logo: .diamond),
        Brand(name: "LUMIQ", background: rgb(0.45, 0.15, 0.7), foreground: .white, accent: rgb(1, 0.6, 0.85), logo: .bars),
        Brand(name: "QUARZA", background: rgb(0.12, 0.12, 0.14), foreground: rgb(1, 0.55, 0.1), accent: rgb(1, 0.55, 0.1), logo: .ring),
        Brand(name: "AXIMO", background: rgb(0.1, 0.5, 0.85), foreground: .white, accent: rgb(1, 0.9, 0.2), logo: .chevrons),
    ]

    private static var cache: [String: Creative] = [:]

    private static var rendererFormat: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return format
    }

    private static func drawPlaceholder(_ brand: Brand, format: AdFormat) -> UIImage {
        let size = format.pixelSize
        return UIGraphicsImageRenderer(size: size, format: rendererFormat).image { ctx in
            let cg = ctx.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            brand.background.setFill()
            cg.fill(bounds)
            // Косая полоса акцентного цвета у правого края.
            brand.accent.withAlphaComponent(0.9).setFill()
            let w = size.width, h = size.height
            cg.move(to: CGPoint(x: w * 0.86, y: 0))
            cg.addLine(to: CGPoint(x: w * 0.92, y: 0))
            cg.addLine(to: CGPoint(x: w * 0.86, y: h))
            cg.addLine(to: CGPoint(x: w * 0.80, y: h))
            cg.fillPath()

            let logoSize = h * 0.6
            let logoRect = CGRect(x: w * 0.06, y: (h - logoSize) / 2, width: logoSize, height: logoSize)
            drawLogo(brand.logo, in: logoRect, color: brand.accent, context: cg)
            let textRect = CGRect(x: logoRect.maxX + w * 0.03, y: 0, width: w * 0.78 - logoRect.maxX - w * 0.03, height: h)
            let font = UIFont.systemFont(ofSize: h * 0.5, weight: .black)
            let italic = font.fontDescriptor.withSymbolicTraits([.traitItalic, .traitBold]).map { UIFont(descriptor: $0, size: h * 0.5) }
            drawCentered(brand.name, in: textRect, font: italic ?? font, color: brand.foreground)
        }
    }

    private static func drawLogo(_ logo: Logo, in r: CGRect, color: UIColor, context cg: CGContext) {
        color.setFill()
        color.setStroke()
        switch logo {
        case .ring:
            cg.setLineWidth(r.width * 0.16)
            cg.strokeEllipse(in: r.insetBy(dx: r.width * 0.1, dy: r.width * 0.1))
        case .dot:
            cg.fillEllipse(in: r.insetBy(dx: r.width * 0.12, dy: r.width * 0.12))
        case .triangle:
            cg.move(to: CGPoint(x: r.midX, y: r.minY))
            cg.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            cg.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            cg.fillPath()
        case .diamond:
            cg.move(to: CGPoint(x: r.midX, y: r.minY))
            cg.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            cg.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            cg.addLine(to: CGPoint(x: r.minX, y: r.midY))
            cg.fillPath()
        case .chevrons:
            cg.setLineWidth(r.width * 0.14)
            cg.setLineJoin(.miter)
            for k in 0..<2 {
                let x = r.minX + r.width * (0.15 + 0.4 * CGFloat(k))
                cg.move(to: CGPoint(x: x, y: r.minY + r.height * 0.1))
                cg.addLine(to: CGPoint(x: x + r.width * 0.35, y: r.midY))
                cg.addLine(to: CGPoint(x: x, y: r.maxY - r.height * 0.1))
            }
            cg.strokePath()
        case .bars:
            for k in 0..<3 {
                let bh = r.height * (0.4 + 0.3 * CGFloat(k))
                cg.fill(CGRect(x: r.minX + r.width * 0.34 * CGFloat(k), y: r.maxY - bh, width: r.width * 0.24, height: bh))
            }
        }
    }

    private static func drawCentered(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        var font = font
        let attributes = { [NSAttributedString.Key.font: font, .foregroundColor: color] }
        var size = (text as NSString).size(withAttributes: attributes())
        // Длинное название ужимается под ширину.
        if size.width > rect.width {
            font = font.withSize(font.pointSize * rect.width / size.width)
            size = (text as NSString).size(withAttributes: attributes())
        }
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes())
    }

    /// Щиты светятся сами (не зависят от освещения), логотипы на траве — как краска, с тенями.
    private static func material(from image: UIImage, lit: Bool) -> RealityKit.Material {
        guard let cg = image.cgImage,
              let texture = try? TextureResource(image: cg, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        else { return SimpleMaterial(color: .gray, isMetallic: false) }
        if lit {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = .init(floatLiteral: 1)
            return material
        }
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(white: 0.92, alpha: 1), texture: .init(texture))
        return material
    }
}
