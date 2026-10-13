// Генерация иконки: swiftc -O tools/make_icon.swift -o /tmp/make_icon && /tmp/make_icon (из корня проекта) → AppIcon.png
import AppKit
import SceneKit

let size = 1024
let usdz = URL(fileURLWithPath: "RaceGame/race_car.usdz")

// MARK: 1. Машина — рендер SceneKit с прозрачным фоном
let scene = try! SCNScene(url: usdz, options: nil)
if let leds = scene.rootNode.childNode(withName: "rain_light_leds_on", recursively: true) { leds.isHidden = true }
let (minB, maxB) = scene.rootNode.boundingBox
let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
let length = max(maxB.z - minB.z, maxB.x - minB.x)

// Повернём машину: едет вверх-вправо по диагонали.
let pivot = SCNNode()
for child in scene.rootNode.childNodes { pivot.addChildNode(child) }
pivot.position = SCNVector3(-center.x, -center.y, -center.z)
let holder = SCNNode()
holder.addChildNode(pivot)
holder.eulerAngles.y = CGFloat(Double.pi * 0.75)
scene.rootNode.addChildNode(holder)

let cam = SCNNode()
cam.camera = SCNCamera()
cam.camera!.usesOrthographicProjection = true
cam.camera!.orthographicScale = Double(length) * 0.74
cam.position = SCNVector3(0, length * 3, length * 1.6)
cam.look(at: SCNVector3(0, 0, 0))
scene.rootNode.addChildNode(cam)

let sun = SCNNode()
sun.light = SCNLight()
sun.light!.type = .directional
sun.light!.intensity = 1100
sun.eulerAngles = SCNVector3(-Double.pi / 2.6, Double.pi / 5, 0)
scene.rootNode.addChildNode(sun)
let amb = SCNNode()
amb.light = SCNLight()
amb.light!.type = .ambient
amb.light!.intensity = 550
scene.rootNode.addChildNode(amb)
scene.background.contents = NSColor.clear

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene
renderer.pointOfView = cam
renderer.autoenablesDefaultLighting = false
let carImage = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)

// MARK: 2. Фон: трава и изогнутая трасса с поребриками
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)
let grass = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.52, green: 0.82, blue: 0.42, alpha: 1), CGColor(red: 0.30, green: 0.62, blue: 0.30, alpha: 1)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grass, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Трасса — дуга из нижнего левого угла в верхний правый (координаты CG: y вверх).
let track = CGMutablePath()
track.move(to: CGPoint(x: -0.1 * s, y: 0.05 * s))
track.addCurve(to: CGPoint(x: 1.1 * s, y: 0.95 * s),
               control1: CGPoint(x: 0.55 * s, y: 0.02 * s), control2: CGPoint(x: 0.45 * s, y: 0.98 * s))
let width: CGFloat = 0.36 * s
ctx.addPath(track); ctx.setLineCap(.butt)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.setLineWidth(width + 0.07 * s); ctx.strokePath()
ctx.addPath(track)
ctx.setStrokeColor(CGColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1)); ctx.setLineWidth(width + 0.07 * s)
ctx.setLineDash(phase: 0, lengths: [0.045 * s, 0.045 * s]); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.addPath(track)
ctx.setStrokeColor(CGColor(red: 0.36, green: 0.37, blue: 0.40, alpha: 1)); ctx.setLineWidth(width); ctx.strokePath()

// Пунктир «траектории пальца» перед машиной.
let trail = CGMutablePath()
trail.move(to: CGPoint(x: 0.62 * s, y: 0.62 * s))
trail.addCurve(to: CGPoint(x: 0.98 * s, y: 0.93 * s),
               control1: CGPoint(x: 0.72 * s, y: 0.78 * s), control2: CGPoint(x: 0.82 * s, y: 0.90 * s))
ctx.addPath(trail)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85)); ctx.setLineWidth(0.022 * s); ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [0.001, 0.05 * s]); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])

// Тень и машина.
var rect = CGRect(x: 0, y: 0, width: s, height: s)
let cgCar = carImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0.012 * s, height: -0.02 * s), blur: 0.03 * s, color: CGColor(gray: 0, alpha: 0.45))
ctx.draw(cgCar, in: CGRect(x: -0.01 * s, y: -0.03 * s, width: s, height: s))
ctx.restoreGState()

let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "AppIcon.png"))
print("done")
