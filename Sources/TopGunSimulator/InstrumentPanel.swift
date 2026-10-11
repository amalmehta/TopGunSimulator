import SwiftUI
import FlightCore

/// The classic "six pack" plus a controls readout showing stick input vs. actual surface deflection.
struct InstrumentPanel: View {
    let t: Telemetry
    let spec: AircraftSpec

    var body: some View {
        HStack(spacing: 10) {
            Gauge("Airspeed") { AirspeedIndicator(kt: t.airspeedKt, spec: spec) }
            Gauge("Attitude") { AttitudeIndicator(pitch: t.pitchDeg, bank: t.bankDeg) }
            Gauge("Altimeter") { Altimeter(ft: t.altitudeFt) }
            Gauge("Turn & slip") { TurnCoordinator(turnRate: t.turnRateDegPerSec, slip: t.slipDeg) }
            Gauge("Heading") { HeadingIndicator(heading: t.headingDeg) }
            Gauge("Vertical speed") { VerticalSpeedIndicator(fpm: t.verticalSpeedFpm, scale: spec.isJet ? 6000 : 2000) }
            ControlsReadout(t: t, spec: spec)
                .frame(width: 210)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.11))
    }
}

private struct Gauge<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(spacing: 3) {
            content
                .aspectRatio(1, contentMode: .fit)
                .background(Circle().fill(Color(white: 0.05)))
                .overlay(Circle().strokeBorder(Color(white: 0.35), lineWidth: 3))
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(white: 0.7))
        }
        .frame(maxWidth: 150)
    }
}

/// Shared helpers for round dials.
private struct Dial {
    let rect: CGRect
    var c: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    var r: CGFloat { min(rect.width, rect.height) / 2 - 4 }
    /// Angle 0 = 12 o'clock, clockwise, in degrees.
    func point(_ angleDeg: Double, _ radius: CGFloat) -> CGPoint {
        let a = (angleDeg - 90).radians
        return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
    }
    func needle(_ ctx: inout GraphicsContext, _ angle: Double, length: CGFloat, width: CGFloat = 3, color: Color = .white) {
        var p = Path()
        p.move(to: point(angle + 180, r * 0.12)); p.addLine(to: point(angle, length))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Color(white: 0.3)))
    }
    func arc(_ ctx: inout GraphicsContext, from a0: Double, to a1: Double, radius: CGFloat, color: Color, width: CGFloat) {
        var p = Path()
        p.addArc(center: c, radius: radius, startAngle: .degrees(a0 - 90), endAngle: .degrees(a1 - 90), clockwise: false)
        ctx.stroke(p, with: .color(color), lineWidth: width)
    }
    func label(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, size: CGFloat = 9) {
        ctx.draw(Text(s).font(.system(size: size, weight: .semibold, design: .rounded)).foregroundColor(.white), at: p)
    }
}

struct AirspeedIndicator: View {
    let kt: Double
    let spec: AircraftSpec
    var body: some View {
        Canvas { ctx, size in
            let d = Dial(rect: CGRect(origin: .zero, size: size))
            let maxKt = spec.vNeKt * 1.15
            func ang(_ v: Double) -> Double { clamp(v / maxKt, 0, 1) * 320 }
            let flapsMax = spec.vApproachKt * 1.4
            d.arc(&ctx, from: ang(spec.vStallKt * 0.9), to: ang(flapsMax), radius: d.r * 0.78, color: .white, width: 3)
            d.arc(&ctx, from: ang(spec.vStallKt), to: ang(spec.vCruiseKt * 1.15), radius: d.r * 0.86, color: .green, width: 4)
            d.arc(&ctx, from: ang(spec.vCruiseKt * 1.15), to: ang(spec.vNeKt), radius: d.r * 0.86, color: .yellow, width: 4)
            d.arc(&ctx, from: ang(spec.vNeKt), to: ang(spec.vNeKt) + 2, radius: d.r * 0.86, color: .red, width: 8)
            let step = spec.isJet ? 200.0 : 40.0
            for v in stride(from: 0, through: maxKt, by: step) {
                d.label(&ctx, "\(Int(v))", at: d.point(ang(v), d.r * 0.62))
            }
            d.label(&ctx, "KNOTS", at: CGPoint(x: d.c.x, y: d.c.y + d.r * 0.3), size: 7)
            d.needle(&ctx, ang(kt), length: d.r * 0.85)
        }
    }
}

struct AttitudeIndicator: View {
    let pitch: Double
    let bank: Double
    var body: some View {
        Canvas { ctx, size in
            let d = Dial(rect: CGRect(origin: .zero, size: size))
            let ppd = d.r / 30
            var inner = ctx
            inner.clip(to: Path(ellipseIn: CGRect(x: d.c.x - d.r, y: d.c.y - d.r, width: d.r * 2, height: d.r * 2)))
            inner.translateBy(x: d.c.x, y: d.c.y)
            inner.rotate(by: .degrees(-bank))
            let horizonY = pitch * ppd
            inner.fill(Path(CGRect(x: -d.r * 2, y: -d.r * 4 + horizonY, width: d.r * 4, height: d.r * 4)), with: .color(Color(red: 0.2, green: 0.5, blue: 0.9)))
            inner.fill(Path(CGRect(x: -d.r * 2, y: horizonY, width: d.r * 4, height: d.r * 4)), with: .color(Color(red: 0.55, green: 0.35, blue: 0.18)))
            var line = Path()
            line.move(to: CGPoint(x: -d.r * 2, y: horizonY)); line.addLine(to: CGPoint(x: d.r * 2, y: horizonY))
            inner.stroke(line, with: .color(.white), lineWidth: 1.5)
            for p in stride(from: -20, through: 20, by: 10) where p != 0 {
                var l = Path()
                let y = horizonY - Double(p) * ppd
                l.move(to: CGPoint(x: -d.r * 0.25, y: y)); l.addLine(to: CGPoint(x: d.r * 0.25, y: y))
                inner.stroke(l, with: .color(.white), lineWidth: 1)
            }
            // Bank scale (fixed) and pointer
            for b in [-60.0, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60] {
                var tick = Path()
                tick.move(to: d.point(b, d.r * 0.88)); tick.addLine(to: d.point(b, d.r * (abs(b).truncatingRemainder(dividingBy: 30) == 0 ? 0.75 : 0.8)))
                ctx.stroke(tick, with: .color(.white), lineWidth: 1.5)
            }
            var pointer = Path()
            pointer.move(to: d.point(-bank, d.r * 0.74)); pointer.addLine(to: d.point(-bank - 5, d.r * 0.62)); pointer.addLine(to: d.point(-bank + 5, d.r * 0.62)); pointer.closeSubpath()
            ctx.fill(pointer, with: .color(.orange))
            // Miniature aircraft
            var plane = Path()
            plane.move(to: CGPoint(x: d.c.x - d.r * 0.5, y: d.c.y)); plane.addLine(to: CGPoint(x: d.c.x - d.r * 0.15, y: d.c.y))
            plane.addLine(to: CGPoint(x: d.c.x, y: d.c.y + d.r * 0.1)); plane.addLine(to: CGPoint(x: d.c.x + d.r * 0.15, y: d.c.y))
            plane.addLine(to: CGPoint(x: d.c.x + d.r * 0.5, y: d.c.y))
            ctx.stroke(plane, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

struct Altimeter: View {
    let ft: Double
    var body: some View {
        Canvas { ctx, size in
            let d = Dial(rect: CGRect(origin: .zero, size: size))
            for i in 0..<10 {
                d.label(&ctx, "\(i)", at: d.point(Double(i) * 36, d.r * 0.72), size: 10)
                var tick = Path()
                tick.move(to: d.point(Double(i) * 36, d.r * 0.95)); tick.addLine(to: d.point(Double(i) * 36, d.r * 0.85))
                ctx.stroke(tick, with: .color(.white), lineWidth: 1.5)
            }
            ctx.draw(Text("\(Int(ft.rounded()))").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.white),
                     at: CGPoint(x: d.c.x, y: d.c.y + d.r * 0.42))
            d.needle(&ctx, (ft / 10_000).truncatingRemainder(dividingBy: 1) * 360, length: d.r * 0.35, width: 2, color: Color(white: 0.75))
            d.needle(&ctx, (ft / 1000).truncatingRemainder(dividingBy: 1) * 360, length: d.r * 0.5, width: 4)
            d.needle(&ctx, (ft / 100).truncatingRemainder(dividingBy: 10) * 36, length: d.r * 0.85, width: 2)
        }
    }
}

struct TurnCoordinator: View {
    let turnRate: Double
    let slip: Double
    var body: some View {
        Canvas { ctx, size in
            let d = Dial(rect: CGRect(origin: .zero, size: size))
            // Standard-rate (3°/s) marks
            for a: Double in [-90, 90, -70, 110] {
                var tick = Path()
                tick.move(to: d.point(a, d.r * 0.92)); tick.addLine(to: d.point(a, d.r * 0.78))
                ctx.stroke(tick, with: .color(.white), lineWidth: 2)
            }
            d.label(&ctx, "L", at: d.point(-70, d.r * 0.62)); d.label(&ctx, "R", at: d.point(70, d.r * 0.62))
            // Aircraft symbol banks with turn rate (20° of symbol = standard rate)
            let tilt = clamp(turnRate / 3 * 20, -40, 40)
            var g = ctx
            g.translateBy(x: d.c.x, y: d.c.y - d.r * 0.05)
            g.rotate(by: .degrees(tilt))
            var wing = Path()
            wing.move(to: CGPoint(x: -d.r * 0.7, y: 0)); wing.addLine(to: CGPoint(x: d.r * 0.7, y: 0))
            wing.move(to: CGPoint(x: 0, y: 0)); wing.addLine(to: CGPoint(x: 0, y: -d.r * 0.18))
            g.stroke(wing, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            // Inclinometer ball
            let tube = CGRect(x: d.c.x - d.r * 0.5, y: d.c.y + d.r * 0.35, width: d.r, height: d.r * 0.2)
            ctx.fill(Path(roundedRect: tube, cornerRadius: d.r * 0.1), with: .color(Color(white: 0.2)))
            let bx = d.c.x + CGFloat(clamp(-slip / 10, -1, 1)) * d.r * 0.4
            ctx.fill(Path(ellipseIn: CGRect(x: bx - d.r * 0.09, y: tube.midY - d.r * 0.09, width: d.r * 0.18, height: d.r * 0.18)), with: .color(.white))
            var lines = Path()
            for x in [d.c.x - d.r * 0.11, d.c.x + d.r * 0.11] { lines.move(to: CGPoint(x: x, y: tube.minY)); lines.addLine(to: CGPoint(x: x, y: tube.maxY)) }
            ctx.stroke(lines, with: .color(.orange), lineWidth: 1)
        }
    }
}

struct HeadingIndicator: View {
    let heading: Double
    var body: some View {
        Canvas { ctx, size in
            let d = Dial(rect: CGRect(origin: .zero, size: size))
            for i in 0..<36 {
                let a = Double(i) * 10 - heading
                var tick = Path()
                tick.move(to: d.point(a, d.r * 0.95)); tick.addLine(to: d.point(a, d.r * (i % 3 == 0 ? 0.8 : 0.87)))
                ctx.stroke(tick, with: .color(.white), lineWidth: 1.2)
                if i % 3 == 0 {
                    let label = [0: "N", 9: "E", 18: "S", 27: "W"][i] ?? "\(i)"
                    d.label(&ctx, label, at: d.point(a, d.r * 0.65), size: 10)
                }
            }
            var plane = Path()
            plane.move(to: CGPoint(x: d.c.x, y: d.c.y - d.r * 0.35)); plane.addLine(to: CGPoint(x: d.c.x, y: d.c.y + d.r * 0.3))
            plane.move(to: CGPoint(x: d.c.x - d.r * 0.25, y: d.c.y - d.r * 0.05)); plane.addLine(to: CGPoint(x: d.c.x + d.r * 0.25, y: d.c.y - d.r * 0.05))
            plane.move(to: CGPoint(x: d.c.x - d.r * 0.1, y: d.c.y + d.r * 0.25)); plane.addLine(to: CGPoint(x: d.c.x + d.r * 0.1, y: d.c.y + d.r * 0.25))
            ctx.stroke(plane, with: .color(.orange), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            var lubber = Path()
            lubber.move(to: d.point(0, d.r)); lubber.addLine(to: d.point(-5, d.r * 0.88)); lubber.addLine(to: d.point(5, d.r * 0.88)); lubber.closeSubpath()
            ctx.fill(lubber, with: .color(.orange))
        }
    }
}

struct VerticalSpeedIndicator: View {
    let fpm: Double
    let scale: Double
    var body: some View {
        Canvas { ctx, size in
            let d = Dial(rect: CGRect(origin: .zero, size: size))
            // 9 o'clock = 0; up is counter... climb = clockwise toward 12, descent toward 6.
            func ang(_ v: Double) -> Double { -90 + clamp(v / scale, -1, 1) * 170 }
            for i in -4...4 {
                let v = Double(i) * scale / 4
                var tick = Path()
                tick.move(to: d.point(ang(v), d.r * 0.95)); tick.addLine(to: d.point(ang(v), d.r * 0.82))
                ctx.stroke(tick, with: .color(.white), lineWidth: 1.5)
                d.label(&ctx, "\(abs(Int(v / 100)))", at: d.point(ang(v), d.r * 0.66), size: 9)
            }
            d.label(&ctx, "UP", at: CGPoint(x: d.c.x + d.r * 0.15, y: d.c.y - d.r * 0.25), size: 7)
            d.label(&ctx, "DN", at: CGPoint(x: d.c.x + d.r * 0.15, y: d.c.y + d.r * 0.25), size: 7)
            d.needle(&ctx, ang(fpm), length: d.r * 0.85)
        }
    }
}

/// Where the pilot's hands and feet are vs. what the control surfaces are doing.
struct ControlsReadout: View {
    let t: Telemetry
    let spec: AircraftSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                stickBox(title: "Stick", x: t.stickRoll, y: -t.stickPitch, color: .white)
                stickBox(title: "Surfaces", x: t.aileron, y: -t.elevator, color: .orange)
                VStack(spacing: 4) {
                    Text("Power").font(.system(size: 9)).foregroundStyle(.secondary)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.2))
                        RoundedRectangle(cornerRadius: 3).fill(t.afterburner ? Color.orange : Color.green)
                            .frame(height: 62 * t.throttle)
                    }
                    .frame(width: 14, height: 62)
                    Text("\(Int(t.throttle * 100))").font(.system(size: 9, design: .monospaced))
                }
            }
            bar(title: "Rudder", value: t.rudder, surface: t.rudderSurface)
            HStack(spacing: 10) {
                Text("Flaps \(Int(t.flapsDeg.rounded()))°")
                Text(String(format: "Trim %+.0f", t.trim * 100))
                if spec.hasRetractableGear { Text(t.gearDown ? "Gear ▼" : "Gear ▲").foregroundStyle(t.gearDown ? .green : .secondary) }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.06)))
    }

    private func stickBox(title: String, x: Double, y: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                var cross = Path()
                cross.move(to: CGPoint(x: 0, y: c.y)); cross.addLine(to: CGPoint(x: size.width, y: c.y))
                cross.move(to: CGPoint(x: c.x, y: 0)); cross.addLine(to: CGPoint(x: c.x, y: size.height))
                ctx.stroke(cross, with: .color(Color(white: 0.3)), lineWidth: 1)
                let p = CGPoint(x: c.x + x * size.width / 2 * 0.9, y: c.y + y * size.height / 2 * 0.9)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(color))
            }
            .frame(width: 62, height: 62)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.15)))
        }
    }

    private func bar(title: String, value: Double, surface: Double) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
            Canvas { ctx, size in
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(Color(white: 0.2)))
                let c = size.width / 2
                let layers: [(Double, Color, CGFloat)] = [(value, .white, size.height), (surface, .orange, size.height * 0.45)]
                for (v, color, h) in layers {
                    let x = c + CGFloat(clamp(v, -1, 1)) * c
                    ctx.fill(Path(CGRect(x: min(c, x), y: (size.height - h) / 2, width: abs(x - c), height: h)), with: .color(color.opacity(0.85)))
                }
            }
            .frame(height: 10)
        }
    }
}
