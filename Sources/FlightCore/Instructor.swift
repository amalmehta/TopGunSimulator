import Foundation
import simd

/// A piece of live coaching: what to do now, and why it matters.
public struct Hint: Identifiable, Equatable {
    public enum Severity: Int, Comparable {
        case info, caution, warning
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }
    public var id: String
    public var severity: Severity
    public var text: String
    public var why: String
}

/// Watches the flight and explains what the aircraft is doing.
/// Stateless apart from a few timers, so it can run every frame.
public struct Instructor {
    private var pitchHoldTime = 0.0
    private var lastPitchInput = 0.0

    public init() {}

    public mutating func evaluate(_ t: Telemetry, spec: AircraftSpec, dt: Double) -> [Hint] {
        var hints: [Hint] = []
        if t.crashed { return hints }
        let airborne = !t.onGround

        // Track how long the pilot has been holding steady pitch pressure (a sign they should trim).
        if abs(t.stickPitch) > 0.08 && abs(t.stickPitch - lastPitchInput) < 0.05 { pitchHoldTime += dt } else { pitchHoldTime = 0 }
        lastPitchInput = t.stickPitch

        if t.stalled {
            hints.append(Hint(id: "stall", severity: .warning,
                text: "STALL: push forward, wings level, full power",
                why: "The wing is past its critical angle of attack (\(Int(t.alphaDeg))°) and has lost lift. Only lowering the angle of attack (stick forward) fixes a stall. Pulling back makes it worse."))
        } else if airborne && t.stallMargin < 0.2 && t.airspeedKt > 5 {
            hints.append(Hint(id: "stallWarning", severity: .caution,
                text: "Stall warning: ease the back pressure",
                why: "Angle of attack is \(Int(t.alphaDeg))°, close to the stall. A wing can stall at any airspeed; it's the angle that matters."))
        }

        if airborne && t.aglFt < 400 && t.verticalSpeedFpm < -1500 {
            hints.append(Hint(id: "sinkRate", severity: .warning,
                text: "SINK RATE: pull up!",
                why: "You're descending at \(Int(-t.verticalSpeedFpm)) fpm only \(Int(t.aglFt)) ft above the ground."))
        } else if airborne && t.aglFt < 200 && !t.gearDown && t.airspeedKt < spec.vApproachKt * 1.3 {
            hints.append(Hint(id: "gear", severity: .warning,
                text: "Gear is up! Press G",
                why: "You're low and slow like you're landing, but the wheels are still retracted."))
        }

        if t.airspeedKt > spec.vNeKt {
            hints.append(Hint(id: "overspeed", severity: .warning,
                text: "Overspeed: reduce power, raise the nose",
                why: "Above the never-exceed speed (\(Int(spec.vNeKt)) kt) the airframe can be damaged."))
        }

        if t.gLoad > spec.gLimit + 0.3 {
            hints.append(Hint(id: "overG", severity: .warning,
                text: String(format: "Over-G (%.1f g): ease off", t.gLoad),
                why: "The structure is rated to \(spec.gLimit) g. Pulling harder doesn't turn you much faster; it bleeds energy."))
        }

        if airborne && abs(t.slipDeg) > 4 && t.airspeedKt > spec.vStallKt * 0.8 && !t.stalled {
            let side = t.slipDeg > 0 ? "right" : "left"
            hints.append(Hint(id: "slip", severity: .info,
                text: "Uncoordinated: step on the \(side) rudder (\(side == "right" ? "E" : "Q"))",
                why: "The aircraft is slipping sideways through the air (\(String(format: "%.0f", abs(t.slipDeg)))°). That adds drag, and near a stall a slip can drop a wing into a spin. Keep the ball centred."))
        }

        if airborne && abs(t.bankDeg) > (spec.kind == .trainer ? 50 : 80) && !t.stalled {
            hints.append(Hint(id: "steepBank", severity: .caution,
                text: "Steep bank (\(Int(abs(t.bankDeg)))°): roll out or add back pressure and power",
                why: "In a bank only part of the lift points up. At 60° you need twice the lift (2 g) just to hold altitude."))
        }

        if airborne && t.verticalSpeedFpm > 300 && t.engine < 0.3 && t.airspeedKt < spec.vClimbKt * 0.9 && !t.stalled {
            hints.append(Hint(id: "climbNoPower", severity: .caution,
                text: "Climbing on low power: you're trading speed for height",
                why: "Pitch controls airspeed and power controls climb. Without power a climb just bleeds airspeed until you stall."))
        }

        if airborne && pitchHoldTime > 5 {
            hints.append(Hint(id: "trim", severity: .info,
                text: "Holding pressure? Trim it out with , and .",
                why: "Trim moves a small tab so the aircraft holds this attitude by itself. Pilots trim constantly so they can fly with a light touch."))
        }

        if t.onGround && t.airspeedKt < 1 && t.throttle < 0.05 && !t.crashed {
            hints.append(Hint(id: "ready", severity: .info,
                text: "Ready for takeoff: full power (R), keep it straight with Q/E, rotate at \(Int(spec.vRotateKt)) kt",
                why: "Raise the nose gently at rotation speed and the wing will lift you off. Don't yank it off early."))
        } else if t.onGround && t.airspeedKt > spec.vRotateKt && t.pitchDeg < 3 && t.throttle > 0.7 {
            hints.append(Hint(id: "rotate", severity: .info,
                text: "Rotate: ease back on the stick (S / ↓)",
                why: "You're past rotation speed (\(Int(spec.vRotateKt)) kt). Raise the nose about 8–10° and let it fly off."))
        }

        return hints.sorted { $0.severity > $1.severity }
    }
}
