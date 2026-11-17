import RealityKit
import UIKit
import simd

/// Объекты у трассы: арка над стартом, рекламные щиты вдоль прямых, логотипы на траве у поворотов,
/// таблички 150 / 100 / 50 м перед торможениями.
@MainActor
extension Track {
    func addTrackside(_ builder: SceneryBuilder) {
        let gray = { (w: CGFloat, metal: Bool) -> RealityKit.Material in
            SimpleMaterial(color: UIColor(white: w, alpha: 1), roughness: metal ? 0.4 : 0.9, isMetallic: metal)
        }
        builder.material("frame") { gray(0.18, false) }
        builder.material("post") { gray(0.55, true) }

        let curvature = signedCurvature()
        addArch(builder)
        addBrakeMarkers(builder, curvature: curvature)
        addBoards(builder, curvature: curvature)
        addGroundLogos(builder, curvature: curvature)
    }

    /// Масштаб объектов у трассы — как у деревьев: на экране машина крупнее реальной.
    private var propScale: Float { definition.carScale / 1.5 }

    /// Кривизна осевой со знаком: > 0 — поворот в сторону +нормали.
    private func signedCurvature() -> [Float] {
        let n = points.count, k = 6
        return (0..<n).map { i in
            let a = tangents[(i - k + n) % n], b = tangents[(i + k) % n]
            return -atan2(a.x * b.y - a.y * b.x, simd_dot(a, b)) / (2 * Float(k) * step)
        }
    }

    private func ground(_ p: SIMD2<Float>, _ y: Float = 0) -> SIMD3<Float> { SIMD3(p.x, y, p.y) }

    /// Вертикаль, наклонённая назад от направления `facing` на `tilt`, — «верх» щита,
    /// повёрнутого лицом к `facing`. Наклон помогает читать щит с высокой камеры.
    private func tilted(_ facing: SIMD2<Float>, tilt: Float) -> (normal: SIMD3<Float>, up: SIMD3<Float>) {
        let f = SIMD3(facing.x, 0, facing.y)
        return (f * cos(tilt) + SIMD3(0, sin(tilt), 0), SIMD3(0, cos(tilt), 0) - f * sin(tilt))
    }

    /// Свободна ли точка: дальше `margin` за поребриком от любого участка трассы и не занята.
    private func clear(_ p: SIMD2<Float>, margin: Float, radius: Float, _ builder: SceneryBuilder) -> Bool {
        approximateDistance(p) > halfWidth + curbWidth + margin && builder.isFree(p, radius: radius)
    }

    // MARK: - Арка

    private func addArch(_ builder: SceneryBuilder) {
        let s = propScale
        let p = points[0], t = tangents[0], nrm = normals[0]
        let span = halfWidth + curbWidth + 1.5 * s
        let height = 7 * s, beam = SIMD3<Float>(2 * span + 1.2 * s, 2.4 * s, 1.2 * s)
        let right = SIMD3(nrm.x, 0, nrm.y), forward = SIMD3(t.x, 0, t.y)
        for side: Float in [-1, 1] {
            let foot = p + nrm * span * side
            builder.add("post", at: p) {
                $0.box(center: ground(foot, height / 2), size: SIMD3(1.2 * s, height, 1.2 * s), right: right, forward: forward)
            }
            builder.reserve(foot, radius: 3 * s)
        }
        let top = ground(p, height + beam.y / 2)
        builder.add("frame", at: p) { $0.box(center: top, size: beam, right: right, forward: forward) }
        // Реклама с обеих сторон перекладины, слегка наклонена к камере.
        for (index, dir) in [(0, -t), (1, t)] {
            let creative = AdContent.creative(for: AdSlot(id: "\(definition.id.rawValue).arch.\(index)", format: .arch, index: index))
            builder.material(creative.id) { creative.material }
            let (normal, up) = tilted(dir, tilt: 0.35)
            let center = top + SIMD3(dir.x, 0, dir.y) * (beam.z / 2 + 0.05)
            builder.add(creative.id, at: p) {
                $0.panel(center: center, normal: normal, up: up, width: beam.x - 0.6 * s, height: beam.y * 1.05)
            }
        }
    }

    // MARK: - Щиты вдоль прямых

    /// Участки, где трасса почти прямая (радиус больше 350 м), — (начало, длина) в индексах осевой.
    private func straights(_ curvature: [Float], minLength: Int) -> [(start: Int, length: Int)] {
        let n = points.count
        let straight = curvature.map { abs($0) < 1 / 350 }
        guard let firstBend = straight.firstIndex(of: false) else { return [(0, n)] }
        var result: [(Int, Int)] = []
        var runStart: Int?
        for k in 1...n {
            let i = (firstBend + k) % n
            if straight[i] {
                if runStart == nil { runStart = firstBend + k }
            } else if let start = runStart {
                if firstBend + k - start >= minLength { result.append((start % n, firstBend + k - start)) }
                runStart = nil
            }
        }
        return result
    }

    private func addBoards(_ builder: SceneryBuilder, curvature: [Float]) {
        let s = propScale
        let width = 12 * s, height = 4 * s, legs = 2.6 * s
        let n = points.count
        var index = 0
        var side: Float = 1
        for run in straights(curvature, minLength: Int(110 / step)) {
            for along in stride(from: Float(50), to: Float(run.length) * step - 30, by: 170) {
                let i = (run.start + Int(along / step)) % n
                side = -side
                let t = tangents[i], nrm = normals[i] * side
                // Щит стоит поперёк трассы лицом к подъезжающим машинам, развёрнут к трассе на 25°.
                let facing = simd_normalize(-t * cos(0.45) - nrm * sin(0.45))
                let center = points[i] + nrm * (halfWidth + curbWidth + 5 * s + width / 2 * 0.9)
                let edge = SIMD2(facing.y, -facing.x) * (width / 2)
                guard clear(center + edge, margin: 3 * s, radius: 0, builder),
                      clear(center - edge, margin: 3 * s, radius: 0, builder),
                      builder.isFree(center, radius: width / 2) else { continue }
                builder.reserve(center, radius: width / 2 + 2 * s)

                let slot = AdSlot(id: "\(definition.id.rawValue).board.\(index)", format: .board, index: index)
                let creative = AdContent.creative(for: slot)
                builder.material(creative.id) { creative.material }
                index += 1

                let (normal, up) = tilted(facing, tilt: 0.3)
                let panelCenter = ground(center, legs) + up * (height / 2)
                let right = simd_normalize(simd_cross(up, normal))
                builder.add("frame", at: center) {
                    $0.box(center: panelCenter - normal * 0.3 * s, size: SIMD3(width + 0.5 * s, height + 0.5 * s, 0.4 * s),
                           right: right, up: up, forward: normal)
                }
                builder.add("post", at: center) {
                    for k: Float in [-0.32, 0.32] {
                        let foot = center + SIMD2(right.x, right.z) * width * k
                        $0.prism(base: ground(foot), radius: 0.25 * s, height: legs + height * 0.5, sides: 6)
                    }
                }
                builder.add(creative.id, at: center) {
                    $0.panel(center: panelCenter + normal * 0.02, normal: normal, up: up, width: width, height: height)
                }
            }
        }
    }

    // MARK: - Логотипы на траве

    private func addGroundLogos(_ builder: SceneryBuilder, curvature: [Float]) {
        let s = propScale
        let width = 15 * s, depth = 5 * s
        let n = points.count
        var index = 0
        var i = 0
        // Вершины поворотов: самая большая кривизна на участке, где радиус меньше 150 м.
        while i < n {
            guard abs(curvature[i]) > 1 / 150 else { i += 1; continue }
            var apex = i
            while i < n && abs(curvature[i]) > 1 / 150 {
                if abs(curvature[i]) > abs(curvature[apex]) { apex = i }
                i += 1
            }
            let t = tangents[apex]
            let outside = normals[apex] * (curvature[apex] > 0 ? -1 : 1)
            let center = points[apex] + outside * (halfWidth + curbWidth + 6 * s + width / 2)
            // Текст читается по ходу движения: «верх» — вперёд по трассе, ширина — поперёк.
            let corners = [center + outside * width / 2, center - outside * width / 2]
            guard corners.allSatisfy({ clear($0, margin: 2 * s, radius: 0, builder) }),
                  builder.isFree(center, radius: width / 2) else { continue }
            builder.reserve(center, radius: width / 2 + 1)
            let slot = AdSlot(id: "\(definition.id.rawValue).ground.\(index)", format: .ground, index: index + 3)
            let creative = AdContent.creative(for: slot)
            builder.material(creative.id) { creative.material }
            index += 1
            builder.add(creative.id, at: center) {
                $0.panel(center: ground(center, 0.05), normal: [0, 1, 0], up: SIMD3(t.x, 0, t.y), width: width, height: depth)
            }
        }
    }

    // MARK: - Таблички торможения

    /// Перед каждым заметным торможением (по профилю скорости соперников) — 150, 100 и 50 м
    /// до конца торможения, с внешней стороны поворота.
    private func addBrakeMarkers(_ builder: SceneryBuilder, curvature: [Float]) {
        let s = propScale
        let profile = SpeedProfile.standard(for: self).speeds
        let n = points.count
        var i = 0
        while i < n {
            guard profile[(i + 1) % n] < profile[i] - 0.001 else { i += 1; continue }
            let start = i
            while profile[(i + 1) % n] < profile[i % n] - 0.001 && i < start + n { i += 1 }
            let end = i % n
            guard profile[start] - profile[end] > 15 else { continue }
            let turn = curvature[(end + Int(20 / step)) % n]
            let side: Float = turn > 0 ? -1 : 1
            for meters in [150, 100, 50] {
                let k = ((end - Int(Float(meters) / step)) % n + n) % n
                let t = tangents[k], nrm = normals[k] * side
                let foot = points[k] + nrm * (halfWidth + curbWidth + 2.5 * s)
                guard clear(foot, margin: 1, radius: 0, builder) else { continue }
                builder.reserve(foot, radius: 3 * s)
                let creative = AdContent.distanceMarker(meters)
                builder.material(creative.id) { creative.material }
                let (normal, up) = tilted(-t, tilt: 0.35)
                let w = 3.6 * s, h = 2.4 * s
                let center = ground(foot, 1.2 * s) + up * (h / 2)
                builder.add("post", at: foot) { $0.prism(base: ground(foot), radius: 0.15 * s, height: 1.2 * s + h * 0.5, sides: 5) }
                builder.add("frame", at: foot) {
                    $0.box(center: center - normal * 0.15 * s, size: SIMD3(w, h, 0.2 * s),
                           right: simd_normalize(simd_cross(up, normal)), up: up, forward: normal)
                }
                builder.add(creative.id, at: foot) {
                    $0.panel(center: center + normal * 0.02, normal: normal, up: up, width: w * 0.94, height: h * 0.9)
                }
            }
        }
    }
}
