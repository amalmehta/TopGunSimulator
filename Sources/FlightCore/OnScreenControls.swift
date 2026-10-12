import Foundation

/// State of the on-screen flight controls (virtual stick, rudder, throttle, hold buttons) and how
/// they merge into the pilot input. Shared logic for the Mac app's mouse/trackpad controls;
/// mirrors web/src/app/touch.ts.
public struct OnScreenControls: Equatable {
    public var active = false
    public var stickHeld = false
    public var pitch = 0.0       // + = stick back (nose up)
    public var roll = 0.0        // + = stick right
    public var yaw = 0.0
    /// Set when the throttle slider moves; consumed by `apply` so the throttle stays where it was left.
    public var throttle: Double?
    public var brakes = false
    public var trigger = false

    public init() {}

    /// Maps a drag offset (points) inside a stick of the given radius to axes in -1...1 with a small
    /// dead zone. Dragging down pulls back (nose up), like a real stick.
    public static func stickAxes(dx: Double, dy: Double, radius: Double, deadZone: Double = 0.08) -> (roll: Double, pitch: Double) {
        var x = dx / radius, y = dy / radius
        let len = (x * x + y * y).squareRoot()
        if len > 1 { x /= len; y /= len }
        func shape(_ v: Double) -> Double {
            abs(v) < deadZone ? 0 : (v < 0 ? -1 : 1) * (abs(v) - deadZone) / (1 - deadZone)
        }
        return (shape(x), shape(y))
    }

    /// Merges on-screen input over keyboard/gamepad input. A held stick overrides pitch and roll.
    public mutating func apply(to input: inout PilotInput, throttle: inout Double, sensitivity: Double) {
        guard active else { return }
        if stickHeld || pitch != 0 || roll != 0 {
            input.pitch = pitch * sensitivity
            input.roll = roll * sensitivity
        }
        if yaw != 0 { input.yaw = yaw }
        if let t = self.throttle { throttle = clamp(t, 0, 1); self.throttle = nil }
        if brakes { input.brakes = 1 }
        if trigger { input.trigger = true }
    }
}
