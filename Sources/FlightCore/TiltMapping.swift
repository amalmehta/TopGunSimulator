import Foundation
import simd

/// The neutral (straight-and-level) hold that tilt is measured from.
public struct TiltNeutral: Equatable {
    public var roll: Double
    public var pitch: Double
}

/// Turns a motion sensor's gravity vector into stick input, relative to a calibrated neutral hold.
/// Used for tilting a game controller in the Mac app (mirrors web/src/app/tilt.ts, which reads a phone).
///
/// The gravity vector is in the controller's own axes with x pointing to the controller's right
/// (Apple's GCMotion frame); it may be in g or m/s², only its direction matters.
public enum TiltMapping {
    public static let defaultRangeDeg = 30.0
    public static let deadZoneDeg = 2.0

    /// Raw roll (right side down = +) and pitch (far edge up = +) angles in radians.
    public static func rawAngles(_ g: Vec3) -> (roll: Double, pitch: Double) {
        let len = simd_length(g)
        guard len > 1e-9 else { return (0, 0) }
        let roll = asin(clamp(g.x / len, -1, 1))
        let pitch = atan2(g.z, -g.y)   // far edge up tips gravity toward the player (+z)
        return (roll, pitch)
    }

    public static func calibrate(_ g: Vec3) -> TiltNeutral {
        let a = rawAngles(g)
        return TiltNeutral(roll: a.roll, pitch: a.pitch)
    }

    /// Stick axes in -1...1: full stick at `rangeDeg` from neutral, with a small dead zone.
    public static func axes(_ g: Vec3, neutral n: TiltNeutral, rangeDeg: Double = defaultRangeDeg,
                            invertPitch: Bool = false) -> (roll: Double, pitch: Double) {
        let a = rawAngles(g)
        var dPitch = a.pitch - n.pitch
        if dPitch > .pi { dPitch -= 2 * .pi }
        if dPitch < -.pi { dPitch += 2 * .pi }
        let range = max(rangeDeg, deadZoneDeg + 1)
        func shape(_ radians: Double) -> Double {
            let d = radians.degrees
            guard abs(d) >= deadZoneDeg else { return 0 }
            return clamp((d < 0 ? -1 : 1) * (abs(d) - deadZoneDeg) / (range - deadZoneDeg), -1, 1)
        }
        let pitch = shape(dPitch)
        return (shape(a.roll - n.roll), invertPitch ? -pitch : pitch)
    }
}
