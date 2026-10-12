import SwiftUI
import FlightCore

/// Fighter-style head-up display. The pitch ladder and flight-path marker are drawn only in the
/// cockpit view, where they line up with the real horizon; other views get the tapes and cues.
struct HUDView: View {
    let frame: FrameSnapshot
    let spec: AircraftSpec
    let camera: CameraMode
    let fov: Double
    /// Height taken by on-screen controls at the bottom; the HUD keeps its readouts clear of it.
    var bottomInset: CGFloat = 0
    @AppStorage(SettingsKey.metricUnits) private var metric = false
    @AppStorage(SettingsKey.instructorLevel) private var instructorLevel = InstructorLevel.explain.rawValue

    private var t: Telemetry { frame.telemetry }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in draw(&ctx, size: size) }
                VStack {
                    Spacer()
                    warningBanner
                        .padding(.bottom, 28 + bottomInset)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder private var warningBanner: some View {
        if let hint = frame.hints.first(where: { $0.severity == .warning }) {
            Text(hint.text)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(HUDColor.warning)
                .shadow(color: .black, radius: 3)
                .opacity(Int(t.time * 3) % 2 == 0 ? 1 : 0.55)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        // A dark halo keeps the green symbology readable over bright sky and terrain.
        ctx.addFilter(.shadow(color: .black.opacity(0.85), radius: 1.2))
        ctx.addFilter(.shadow(color: .black.opacity(0.5), radius: 3))
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let green = HUDColor.symbology
        let ppd = size.height / fov  // pixels per degree (vertical field of view)
        let font = Font.system(size: 13, weight: .semibold, design: .monospaced)
        let fmt = UnitFormatter(metric: metric)

        func text(_ s: String, _ p: CGPoint, anchor: UnitPoint = .center, color: Color = green, size: CGFloat = 13) {
            ctx.draw(Text(s).font(.system(size: size, weight: .semibold, design: .monospaced)).foregroundColor(color), at: p, anchor: anchor)
        }
        func stroke(_ path: Path, _ color: Color = green, width: CGFloat = 1.6) {
            ctx.stroke(path, with: .color(color.opacity(0.9)), lineWidth: width)
        }

        // Pitch ladder + flight path marker (cockpit only)
        if camera == .cockpit {
            var ladder = ctx
            ladder.translateBy(x: c.x, y: c.y)
            ladder.rotate(by: .degrees(-t.bankDeg))
            for deg in stride(from: -90, through: 90, by: 5) {
                let y = (t.pitchDeg - Double(deg)) * ppd
                guard abs(y) < size.height * 0.42 else { continue }
                let w: CGFloat = deg == 0 ? size.width * 0.35 : (deg % 10 == 0 ? 90 : 40)
                var p = Path()
                if deg == 0 {
                    p.move(to: CGPoint(x: -w, y: y)); p.addLine(to: CGPoint(x: -40, y: y))
                    p.move(to: CGPoint(x: 40, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                } else {
                    p.move(to: CGPoint(x: -w, y: y)); p.addLine(to: CGPoint(x: -30, y: y))
                    p.move(to: CGPoint(x: 30, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                }
                ladder.stroke(p, with: .color(green.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, dash: deg < 0 ? [8, 6] : []))
                if deg != 0 && deg % 10 == 0 {
                    ladder.draw(Text("\(abs(deg))").font(font).foregroundColor(green), at: CGPoint(x: w + 16, y: y))
                    ladder.draw(Text("\(abs(deg))").font(font).foregroundColor(green), at: CGPoint(x: -w - 16, y: y))
                }
            }
            // Flight path marker: where the aircraft is actually going.
            let fpm = CGPoint(x: c.x + t.slipDeg * ppd, y: c.y + t.alphaDeg * ppd)
            if abs(fpm.x - c.x) < size.width / 2 && abs(fpm.y - c.y) < size.height / 2 {
                var m = Path(ellipseIn: CGRect(x: fpm.x - 7, y: fpm.y - 7, width: 14, height: 14))
                m.move(to: CGPoint(x: fpm.x - 20, y: fpm.y)); m.addLine(to: CGPoint(x: fpm.x - 7, y: fpm.y))
                m.move(to: CGPoint(x: fpm.x + 7, y: fpm.y)); m.addLine(to: CGPoint(x: fpm.x + 20, y: fpm.y))
                m.move(to: CGPoint(x: fpm.x, y: fpm.y - 7)); m.addLine(to: CGPoint(x: fpm.x, y: fpm.y - 15))
                stroke(m, width: 2)
            }
            // Waterline / gun cross
            var w = Path()
            w.move(to: CGPoint(x: c.x - 26, y: c.y)); w.addLine(to: CGPoint(x: c.x - 12, y: c.y))
            w.addLine(to: CGPoint(x: c.x - 6, y: c.y + 8)); w.addLine(to: CGPoint(x: c.x, y: c.y))
            w.addLine(to: CGPoint(x: c.x + 6, y: c.y + 8)); w.addLine(to: CGPoint(x: c.x + 12, y: c.y))
            w.addLine(to: CGPoint(x: c.x + 26, y: c.y))
            stroke(w)
        }

        // Heading tape
        let tapeY: CGFloat = 26
        var tape = Path()
        for off in stride(from: -30, through: 30, by: 5) {
            let hdg = (Int(t.headingDeg.rounded()) / 5) * 5 + off
            let x = c.x + CGFloat(Double(hdg) - t.headingDeg) * 6
            let major = hdg % 10 == 0
            tape.move(to: CGPoint(x: x, y: tapeY)); tape.addLine(to: CGPoint(x: x, y: tapeY + (major ? 10 : 5)))
            if major {
                let h = (hdg % 360 + 360) % 360
                let label = [0: "N", 90: "E", 180: "S", 270: "W"][h] ?? String(format: "%02d", h / 10)
                text(label, CGPoint(x: x, y: tapeY + 22), size: 11)
            }
        }
        stroke(tape, width: 1.2)
        var caret = Path()
        caret.move(to: CGPoint(x: c.x - 6, y: tapeY - 8)); caret.addLine(to: CGPoint(x: c.x, y: tapeY - 1)); caret.addLine(to: CGPoint(x: c.x + 6, y: tapeY - 8))
        stroke(caret, width: 2)
        text(String(format: "%03d°", Int(t.headingDeg.rounded()) % 360), CGPoint(x: c.x, y: tapeY + 40), size: 15)

        // Speed (left) and altitude (right) boxes
        let boxY = bottomInset > 0 ? max(90, (size.height - bottomInset) / 2) : c.y
        let leftX = c.x - min(size.width * 0.32, 340), rightX = c.x + min(size.width * 0.32, 340)
        for (x, value, label) in [(leftX, fmt.speed(t.airspeedKt), "IAS"), (rightX, fmt.altitude(t.altitudeFt), "ALT")] {
            let r = CGRect(x: x - 58, y: boxY - 16, width: 116, height: 32)
            stroke(Path(roundedRect: r, cornerRadius: 4), width: 1.6)
            text(value, CGPoint(x: x, y: boxY), size: 17)
            text(label, CGPoint(x: x, y: boxY - 28), size: 11)
        }
        text(fmt.vertical(t.verticalSpeedFpm), CGPoint(x: rightX, y: boxY + 32))
        text("AGL " + fmt.altitude(t.aglFt), CGPoint(x: rightX, y: boxY + 50), size: 12)
        text(String(format: "G %.1f", t.gLoad), CGPoint(x: leftX, y: boxY + 32))
        let aoaColor = t.stallMargin < 0.2 ? HUDColor.warning : green
        text(String(format: "α %.1f°", t.alphaDeg), CGPoint(x: leftX, y: boxY + 50), color: aoaColor, size: 12)
        if spec.isJet {
            text(String(format: "M %.2f", t.airspeedKt * Units.knot / 340), CGPoint(x: leftX, y: boxY + 68), size: 12)
        }

        // Speed trend cues: stall and never-exceed
        if t.airspeedKt < spec.vStallKt * 1.15 && !t.onGround {
            text("SPEED", CGPoint(x: leftX, y: boxY - 48), color: HUDColor.warning, size: 13)
        }

        // Systems strip: bottom-left normally, top-left (beside the heading tape) with on-screen controls.
        let sysY = bottomInset > 0 ? 14 : size.height - 70
        let rowStep: CGFloat = bottomInset > 0 ? 16 : -20
        var sys = "THR \(Int(t.throttle * 100))%"
        if t.afterburner { sys += " AB" }
        sys += "   FLAPS \(Int(t.flapsDeg.rounded()))°"
        if spec.hasRetractableGear { sys += t.gearDown ? "   GEAR DN" : "   GEAR UP" }
        sys += String(format: "   TRIM %+.0f", t.trim * 100)
        if t.brakes > 0 { sys += "   BRK" }
        text(sys, CGPoint(x: 18, y: sysY), anchor: .leading, size: 12)

        // Combat cues
        if spec.isJet && frame.banditPosition != nil {
            let pip = Path(ellipseIn: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36))
            stroke(pip, width: 1.2)
            text("GUN \(frame.ammo)", CGPoint(x: 18, y: sysY + rowStep), anchor: .leading, size: 12)
            if let d = frame.banditDistance {
                text(String(format: "BANDIT %.1f nm  %d%%", d / 1852, Int(frame.banditHealth)), CGPoint(x: 18, y: sysY + rowStep * 2), anchor: .leading, color: HUDColor.bandit, size: 12)
            }
            if let p = frame.banditScreen, CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 20).contains(p) {
                let box = Path(CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32))
                stroke(box, HUDColor.bandit, width: 2)
                if let d = frame.banditDistance { text("\(Int(d)) m", CGPoint(x: p.x, y: p.y + 28), color: HUDColor.bandit, size: 11) }
            } else if let bp = frame.banditPosition, frame.banditHealth > 0 {
                drawOffscreenArrow(&ctx, size: size, center: c, toward: bp, color: HUDColor.bandit)
            }
        }
        if let p = frame.nextGateScreen, CGRect(origin: .zero, size: size).contains(p) {
            var d = Path()
            d.move(to: CGPoint(x: p.x, y: p.y - 12)); d.addLine(to: CGPoint(x: p.x + 12, y: p.y))
            d.addLine(to: CGPoint(x: p.x, y: p.y + 12)); d.addLine(to: CGPoint(x: p.x - 12, y: p.y)); d.closeSubpath()
            stroke(d, HUDColor.gate, width: 2)
        }
        if t.health < 100 {
            text("DAMAGE \(100 - Int(t.health))%", CGPoint(x: size.width - 18, y: sysY), anchor: .trailing, color: HUDColor.warning, size: 12)
        }
    }

    /// Points to something behind or beside the camera, relative to the aircraft's nose.
    private func drawOffscreenArrow(_ ctx: inout GraphicsContext, size: CGSize, center c: CGPoint, toward p: Vec3, color: Color) {
        // Bearing relative to heading on the horizontal plane, and elevation relative to us.
        let me = t.position
        let rel = p - me
        let bearing = headingDelta(wrap360(atan2(rel.x, -rel.z).degrees), t.headingDeg)
        let horiz = (rel.x * rel.x + rel.z * rel.z).squareRoot()
        let elev = atan2(rel.y, horiz).degrees
        let angle = atan2(-elev, bearing)
        let r = min(size.width, size.height) * 0.36
        let pos = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
        var tri = Path()
        tri.move(to: CGPoint(x: 14, y: 0)); tri.addLine(to: CGPoint(x: -8, y: -9)); tri.addLine(to: CGPoint(x: -8, y: 9)); tri.closeSubpath()
        var g = ctx
        g.translateBy(x: pos.x, y: pos.y)
        g.rotate(by: .radians(angle))
        g.fill(tri, with: .color(color))
    }
}
