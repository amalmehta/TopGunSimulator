import SwiftUI
import FlightCore

/// Mouse/trackpad flight controls over the 3D view: stick bottom-left (rudder above it),
/// buttons and throttle bottom-right. Mirrors the website's touch controls.
struct OnScreenControlsView: View {
    @EnvironmentObject var sim: SimulationController
    let telemetry: Telemetry
    let spec: AircraftSpec
    static let stickSize: CGFloat = 132
    /// Height the controls take at the bottom of the 3D view (the HUD keeps its readouts above it).
    static let inset: CGFloat = 180

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        HoldButton(label: "◀ Rudder") { sim.input.onScreen.yaw = $0 ? -1 : 0 }
                        HoldButton(label: "Rudder ▶") { sim.input.onScreen.yaw = $0 ? 1 : 0 }
                    }
                    StickView(size: Self.stickSize)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.fixed(64)), GridItem(.fixed(64))], spacing: 6) {
                        ActionButton(label: "Flaps ▲") { sim.handle(.flapsUp) }
                        ActionButton(label: "Flaps ▼") { sim.handle(.flapsDown) }
                        ActionButton(label: "Trim ▲") { sim.handle(.trimUp) }
                        ActionButton(label: "Trim ▼") { sim.handle(.trimDown) }
                        if spec.hasRetractableGear { ActionButton(label: "Gear") { sim.handle(.toggleGear) } }
                        ActionButton(label: "Cam") { sim.handle(.nextCamera) }
                        HoldButton(label: "Brake") { sim.input.onScreen.brakes = $0 }
                        if spec.isJet { HoldButton(label: "Guns", tint: .red) { sim.input.onScreen.trigger = $0 } }
                    }
                    .frame(width: 134)
                    ThrottleView(value: telemetry.throttle, height: Self.stickSize) { sim.input.onScreen.throttle = $0 }
                }
            }
            .padding(16)
        }
    }
}

/// Virtual stick: drag the knob; it springs back to centre on release.
private struct StickView: View {
    @EnvironmentObject var sim: SimulationController
    let size: CGFloat
    @State private var offset = CGSize.zero

    var body: some View {
        let r = size / 2
        ZStack {
            Circle().fill(.white.opacity(0.12))
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2)
            Path { p in
                p.move(to: CGPoint(x: r, y: size * 0.1)); p.addLine(to: CGPoint(x: r, y: size * 0.9))
                p.move(to: CGPoint(x: size * 0.1, y: r)); p.addLine(to: CGPoint(x: size * 0.9, y: r))
            }
            .stroke(.white.opacity(0.25), lineWidth: 1)
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .offset(offset)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    var dx = g.location.x - r, dy = g.location.y - r
                    let len = (dx * dx + dy * dy).squareRoot()
                    if len > r { dx *= r / len; dy *= r / len }
                    offset = CGSize(width: dx, height: dy)
                    let a = OnScreenControls.stickAxes(dx: dx, dy: dy, radius: r)
                    sim.input.onScreen.stickHeld = true
                    sim.input.onScreen.roll = a.roll
                    sim.input.onScreen.pitch = a.pitch
                }
                .onEnded { _ in
                    offset = .zero
                    sim.input.onScreen.stickHeld = false
                    sim.input.onScreen.roll = 0
                    sim.input.onScreen.pitch = 0
                }
        )
        .help("Stick: drag down to pull back (nose up), sideways to roll")
    }
}

/// Vertical throttle: click or drag to set; it stays where you leave it.
private struct ThrottleView: View {
    let value: Double
    let height: CGFloat
    let onSet: (Double) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.45))
            RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.75))
                .frame(height: height * CGFloat(clamp(value, 0, 1)))
            VStack {
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                Spacer()
            }
        }
        .frame(width: 44, height: height)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.4)))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in onSet(clamp(1 - Double(g.location.y / height), 0, 1)) }
        )
        .help("Throttle: drag up for more power")
    }
}

/// Fires once per click.
private struct ActionButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { ControlLabel(label: label, pressed: false) }
            .buttonStyle(.plain)
    }
}

/// Active while the mouse button is held down.
private struct HoldButton: View {
    let label: String
    var tint: Color = .black
    let onChange: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        ControlLabel(label: label, pressed: pressed, tint: tint)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true; onChange(true) } }
                    .onEnded { _ in pressed = false; onChange(false) }
            )
            .help("Hold")
    }
}

private struct ControlLabel: View {
    let label: String
    let pressed: Bool
    var tint: Color = .black
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 58, minHeight: 32)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 9).fill(pressed ? Color.accentColor.opacity(0.75) : tint.opacity(tint == .black ? 0.45 : 0.6)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.4)))
            .contentShape(Rectangle())
    }
}
