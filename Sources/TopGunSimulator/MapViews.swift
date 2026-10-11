import SwiftUI
import AppKit
import FlightCore
import simd

/// Pre-rendered terrain image for the 2D map (north up).
enum TerrainImage {
    static let minX = -22_000.0, maxX = 22_000.0, minZ = -32_000.0, maxZ = 12_000.0
    static let image: NSImage = {
        let px = 440
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for j in 0..<px {
            for i in 0..<px {
                let x = minX + (maxX - minX) * (Double(i) + 0.5) / Double(px)
                let z = minZ + (maxZ - minZ) * (Double(j) + 0.5) / Double(px)
                let h = Terrain.height(x: x, z: z)
                let n = Terrain.normal(x: x, z: z)
                let c = WorldScene.groundColor(height: h, slope: 1 - n.y, x: x, z: z)
                let shade = Float(0.75 + 0.45 * simd_dot(n, simd_normalize(Vec3(-0.6, 0.7, -0.4))))
                let px = rep.bitmapData! + j * rep.bytesPerRow + i * 4
                px[0] = UInt8(clamp(c.x * shade, 0, 1) * 255)
                px[1] = UInt8(clamp(c.y * shade, 0, 1) * 255)
                px[2] = UInt8(clamp(c.z * shade, 0, 1) * 255)
                px[3] = 255
            }
        }
        let img = NSImage(size: NSSize(width: px, height: px))
        img.addRepresentation(rep)
        return img
    }()
}

/// Top-down moving map: terrain, runway, gates, your track and the bandit.
struct MapView: View {
    let frame: FrameSnapshot
    @State private var metersPerPoint = 30.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in draw(&ctx, size: size) }
                .clipped()
            VStack(spacing: 4) {
                Button { metersPerPoint = max(5, metersPerPoint / 1.6) } label: { Image(systemName: "plus") }
                Button { metersPerPoint = min(250, metersPerPoint * 1.6) } label: { Image(systemName: "minus") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(6)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let me = frame.telemetry.position
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let s = metersPerPoint
        func pt(_ x: Double, _ z: Double) -> CGPoint { CGPoint(x: c.x + (x - me.x) / s, y: c.y + (z - me.z) / s) }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.43, green: 0.56, blue: 0.33)))
        let tl = pt(TerrainImage.minX, TerrainImage.minZ), br = pt(TerrainImage.maxX, TerrainImage.maxZ)
        // Bitmap row 0 is the northern edge (minZ), which is the top of the map.
        ctx.draw(Image(nsImage: TerrainImage.image), in: CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y))

        // Runway
        let rw = CGRect(x: pt(-Terrain.runwayWidth / 2, 0).x, y: pt(0, Terrain.runwayNorthEnd).y,
                        width: max(Terrain.runwayWidth / s, 2), height: Terrain.runwayLength / s)
        ctx.fill(Path(rw), with: .color(Color(white: 0.2)))
        ctx.stroke(Path(rw), with: .color(.white.opacity(0.8)), lineWidth: 0.8)

        // Gates
        for g in frame.gates {
            let p = pt(g.center.x, g.center.z)
            let r = max(g.radius / s, 3)
            let color: Color = g.status == .passed ? .green : (g.status == .missed ? .gray : HUDColor.gate)
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 2)
        }

        // Tracks
        func polyline(_ pts: [Vec3]) -> Path {
            var path = Path()
            for (i, v) in pts.enumerated() { i == 0 ? path.move(to: pt(v.x, v.z)) : path.addLine(to: pt(v.x, v.z)) }
            return path
        }
        ctx.stroke(polyline(frame.trail + [me]), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        if let b = frame.banditPosition {
            ctx.stroke(polyline(frame.banditTrail + [b]), with: .color(HUDColor.bandit.opacity(0.7)), lineWidth: 1.2)
            drawPlane(&ctx, at: pt(b.x, b.z), heading: frame.banditHeading, color: HUDColor.bandit)
        }
        drawPlane(&ctx, at: c, heading: frame.telemetry.headingDeg, color: .yellow)

        // Scale bar
        let barMeters: Double = [100.0, 250, 500, 1000, 2000, 5000].last(where: { $0 / s < size.width * 0.35 }) ?? 100
        let barLen = barMeters / s
        var bar = Path()
        bar.move(to: CGPoint(x: 10, y: size.height - 12)); bar.addLine(to: CGPoint(x: 10 + barLen, y: size.height - 12))
        ctx.stroke(bar, with: .color(.white), lineWidth: 2)
        ctx.draw(Text(barMeters >= 1000 ? "\(Int(barMeters / 1000)) km" : "\(Int(barMeters)) m").font(.caption2).foregroundColor(.white),
                 at: CGPoint(x: 10 + barLen / 2, y: size.height - 22))
        ctx.draw(Text("N ↑").font(.caption.bold()).foregroundColor(.white), at: CGPoint(x: 18, y: 14))
    }

    private func drawPlane(_ ctx: inout GraphicsContext, at p: CGPoint, heading: Double, color: Color) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(heading))
        var tri = Path()
        tri.move(to: CGPoint(x: 0, y: -9)); tri.addLine(to: CGPoint(x: 6, y: 7)); tri.addLine(to: CGPoint(x: 0, y: 4)); tri.addLine(to: CGPoint(x: -6, y: 7)); tri.closeSubpath()
        g.fill(tri, with: .color(color))
        g.stroke(tri, with: .color(.black.opacity(0.6)), lineWidth: 1)
    }
}

/// Side view along your current track: terrain ahead, your altitude, and (near the field) the 3° glidepath.
struct ProfileView: View {
    let frame: FrameSnapshot
    let showGlidepath: Bool

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size: size) }
            .background(Color(red: 0.62, green: 0.78, blue: 0.93))
            .clipped()
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let t = frame.telemetry
        let me = t.position
        let track = t.groundSpeedKt > 5 ? t.trackDeg : t.headingDeg
        let dir = Vec3(sin(track.radians), 0, -cos(track.radians))
        let behind = 1500.0, ahead = 6000.0
        // Sample terrain along the track.
        var samples: [(Double, Double)] = []
        for d in stride(from: -behind, through: ahead, by: 60) {
            let p = me + dir * d
            samples.append((d, Terrain.height(x: p.x, z: p.z)))
        }
        let maxTerrain = samples.map(\.1).max() ?? 0
        let top = max(me.y, maxTerrain) + max(200, max(me.y, maxTerrain) * 0.35)
        let bottom = max(0, min(me.y, samples.map(\.1).min() ?? 0) - 60)
        func pt(_ d: Double, _ alt: Double) -> CGPoint {
            CGPoint(x: (d + behind) / (ahead + behind) * size.width, y: size.height - (alt - bottom) / (top - bottom) * size.height)
        }

        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: size.height))
        for (d, h) in samples { ground.addLine(to: pt(d, h)) }
        ground.addLine(to: CGPoint(x: size.width, y: size.height))
        ground.closeSubpath()
        ctx.fill(ground, with: .color(Color(red: 0.38, green: 0.5, blue: 0.3)))

        // Glidepath to runway 36 when flying roughly north near the field.
        if showGlidepath && abs(headingDelta(track, 0)) < 45 && me.z > Terrain.runwayNorthEnd && me.z < Terrain.runwaySouthEnd + 8000 && abs(me.x) < 2000 {
            let touchdownZ = Terrain.runwaySouthEnd - 300
            var gp = Path()
            for d in stride(from: -behind, through: ahead, by: 100) {
                let z = me.z - d   // moving north reduces z
                let dist = z - touchdownZ
                let alt = max(0, dist * tan(3.radians))
                d == -behind ? gp.move(to: pt(d, alt)) : gp.addLine(to: pt(d, alt))
            }
            ctx.stroke(gp, with: .color(.purple.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            ctx.draw(Text("3° glidepath").font(.caption2).foregroundColor(.purple), at: CGPoint(x: size.width - 50, y: 10))
        }

        // Your recent altitude history, projected onto the track.
        var hist = Path()
        var started = false
        for p in frame.trail.suffix(60) {
            let d = simd_dot(p - me, dir)
            guard d > -behind else { continue }
            started ? hist.addLine(to: pt(d, p.y)) : hist.move(to: pt(d, p.y))
            started = true
        }
        if started {
            hist.addLine(to: pt(0, me.y))
            ctx.stroke(hist, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }

        // Aircraft symbol pitched to the actual attitude.
        var g = ctx
        let p = pt(0, me.y)
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(-t.pitchDeg))
        var plane = Path()
        plane.move(to: CGPoint(x: 10, y: 0)); plane.addLine(to: CGPoint(x: -8, y: -2)); plane.addLine(to: CGPoint(x: -10, y: -7))
        plane.addLine(to: CGPoint(x: -12, y: -7)); plane.addLine(to: CGPoint(x: -11, y: 2)); plane.closeSubpath()
        g.fill(plane, with: .color(.yellow))
        g.stroke(plane, with: .color(.black), lineWidth: 0.8)

        let fmt = UnitFormatter(metric: UserDefaults.standard.bool(forKey: SettingsKey.metricUnits))
        ctx.draw(Text("AGL \(fmt.altitude(t.aglFt))").font(.caption.monospacedDigit()).foregroundColor(.black), at: CGPoint(x: 8, y: 10), anchor: .leading)
        ctx.draw(Text("← 1.5 km   ahead 6 km →").font(.caption2).foregroundColor(.black.opacity(0.6)), at: CGPoint(x: size.width / 2, y: size.height - 8))
    }
}
