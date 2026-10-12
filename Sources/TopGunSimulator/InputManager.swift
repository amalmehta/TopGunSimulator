import AppKit
import GameController
import FlightCore
import simd

/// Discrete actions triggered by a key press.
enum FlightAction {
    case flapsUp, flapsDown, toggleGear, trimUp, trimDown, nextCamera, togglePause, toggleHelp, toggleSidebar, toggleInstruments, toggleOnScreenControls, levelTilt, endFlight, restart
}

/// Turns keyboard and game-controller state into smooth stick, rudder and throttle inputs.
final class InputManager {
    private var pressed = Set<UInt16>()
    private var monitor: Any?
    var onAction: ((FlightAction) -> Void)?

    // Smoothed keyboard axes
    private var kbPitch = 0.0, kbRoll = 0.0, kbYaw = 0.0
    var throttle = 0.0
    /// On-screen stick/rudder/throttle (mouse or trackpad), merged over keyboard and gamepad.
    var onScreen = OnScreenControls()

    // Controller tilt (motion sensor in a DualSense / DualShock 4 or similar)
    private var tiltNeutral: TiltNeutral?
    private var filteredGravity: Vec3?
    private var levelButtonWasDown = false
    /// True while motion data from a controller is arriving.
    private(set) var tiltReceiving = false

    /// Makes the controller's current hold straight and level (recalibrates on the next sample).
    func levelTilt() { tiltNeutral = nil }

    /// Names of connected controllers and whether they have a motion sensor, for Settings.
    static func motionControllerStatus() -> String {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        guard !pads.isEmpty else { return "No game controller connected." }
        return pads.map { c in
            let name = c.vendorName ?? "Controller"
            return c.motion != nil ? "\(name): motion sensor available" : "\(name): no motion sensor"
        }.joined(separator: "\n")
    }

    enum Key {
        static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, f: UInt16 = 3, h: UInt16 = 4, g: UInt16 = 5
        static let c: UInt16 = 8, b: UInt16 = 11, q: UInt16 = 12, w: UInt16 = 13, e: UInt16 = 14, r: UInt16 = 15
        static let rightBracket: UInt16 = 30, leftBracket: UInt16 = 33, i: UInt16 = 34, p: UInt16 = 35
        static let comma: UInt16 = 43, m: UInt16 = 46, period: UInt16 = 47, space: UInt16 = 49, escape: UInt16 = 53
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let backslash: UInt16 = 42, k: UInt16 = 40, l: UInt16 = 37
    }

    static let flightKeys: Set<UInt16> = [Key.a, Key.s, Key.d, Key.f, Key.h, Key.g, Key.c, Key.b, Key.q, Key.w, Key.e, Key.r,
                                          Key.rightBracket, Key.leftBracket, Key.i, Key.p, Key.comma, Key.m, Key.period,
                                          Key.space, Key.escape, Key.left, Key.right, Key.down, Key.up, Key.backslash, Key.k, Key.l]

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            // Let text fields (feedback, settings) have their keys, and leave ⌘-shortcuts alone.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            if event.modifierFlags.contains(.command) { return event }
            guard Self.flightKeys.contains(event.keyCode) else { return event }
            if event.type == .keyDown {
                if !event.isARepeat { self.keyPressed(event.keyCode) }
                self.pressed.insert(event.keyCode)
            } else {
                self.pressed.remove(event.keyCode)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pressed.removeAll()
    }

    private func keyPressed(_ code: UInt16) {
        switch code {
        case Key.rightBracket: onAction?(.flapsDown)
        case Key.leftBracket: onAction?(.flapsUp)
        case Key.g: onAction?(.toggleGear)
        case Key.period: onAction?(.trimUp)
        case Key.comma: onAction?(.trimDown)
        case Key.c: onAction?(.nextCamera)
        case Key.p: onAction?(.togglePause)
        case Key.h: onAction?(.toggleHelp)
        case Key.m: onAction?(.toggleSidebar)
        case Key.i: onAction?(.toggleInstruments)
        case Key.escape: onAction?(.endFlight)
        case Key.backslash: onAction?(.restart)
        case Key.k: onAction?(.toggleOnScreenControls)
        case Key.l: onAction?(.levelTilt)
        default: break
        }
    }

    /// Reads all devices and returns the pilot input for this frame.
    func sample(dt: Double, settings: SimSettings) -> PilotInput {
        func held(_ codes: UInt16...) -> Bool { codes.contains { pressed.contains($0) } }
        func axis(_ current: Double, plus: Bool, minus: Bool, rate: Double) -> Double {
            let target: Double = plus == minus ? 0 : (plus ? 1 : -1)
            let speed = target == 0 ? rate * 2.5 * settings.keyboardCentering : rate
            if current < target { return min(target, current + speed * dt) }
            return max(target, current - speed * dt)
        }

        // Keyboard works like a stick: S/↓ = pull back (nose up), W/↑ = push forward.
        kbPitch = axis(kbPitch, plus: held(Key.s, Key.down), minus: held(Key.w, Key.up), rate: 1.6)
        kbRoll = axis(kbRoll, plus: held(Key.d, Key.right), minus: held(Key.a, Key.left), rate: 2.5)
        kbYaw = axis(kbYaw, plus: held(Key.e), minus: held(Key.q), rate: 2.5)
        if held(Key.r) { throttle = min(1, throttle + 0.5 * dt) }
        if held(Key.f) { throttle = max(0, throttle - 0.5 * dt) }

        var input = PilotInput()
        let sensitivity = settings.stickSensitivity
        input.pitch = kbPitch * 0.75 * sensitivity
        input.roll = kbRoll * 0.8 * sensitivity
        input.yaw = kbYaw
        input.brakes = held(Key.b) ? 1 : 0
        input.trigger = held(Key.space)

        tiltReceiving = false
        if let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }), let pad = controller.extendedGamepad {
            let dead = { (v: Float) -> Double in abs(v) < 0.08 ? 0 : Double(v) }
            let ly = dead(pad.leftThumbstick.yAxis.value)
            let lx = dead(pad.leftThumbstick.xAxis.value)
            let rx = dead(pad.rightThumbstick.xAxis.value)
            if ly != 0 { input.pitch = -ly * sensitivity }     // stick back (down) = nose up
            if lx != 0 { input.roll = lx * sensitivity }
            if rx != 0 { input.yaw = rx }
            let r2 = Double(pad.rightTrigger.value), l2 = Double(pad.leftTrigger.value)
            if r2 > 0.05 { throttle = min(1, throttle + r2 * 0.6 * dt) }
            if l2 > 0.05 { throttle = max(0, throttle - l2 * 0.6 * dt) }
            if pad.buttonA.isPressed { input.trigger = true }
            if pad.buttonB.isPressed { input.brakes = 1 }

            // Tilt: flies when the controller's stick is centred. Pressing the left stick (L3) levels it.
            if settings.controllerTilt, let motion = controller.motion {
                if motion.sensorsRequireManualActivation && !motion.sensorsActive { motion.sensorsActive = true }
                let raw: Vec3 = motion.hasGravityAndUserAcceleration
                    ? Vec3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
                    : Vec3(motion.acceleration.x, motion.acceleration.y, motion.acceleration.z)
                if simd_length(raw) > 0.1 {
                    // Total acceleration includes hand jitter; smooth it so only the tilt comes through.
                    let k = motion.hasGravityAndUserAcceleration ? 1 : min(1, dt * 8)
                    let g = filteredGravity.map { $0 + (raw - $0) * k } ?? raw
                    filteredGravity = g
                    tiltReceiving = true
                    let l3 = pad.leftThumbstickButton?.isPressed ?? false
                    if l3 && !levelButtonWasDown { tiltNeutral = nil }
                    levelButtonWasDown = l3
                    if tiltNeutral == nil { tiltNeutral = TiltMapping.calibrate(g) }
                    if lx == 0 && ly == 0, let n = tiltNeutral {
                        let a = TiltMapping.axes(g, neutral: n, rangeDeg: settings.tiltRangeDeg, invertPitch: settings.tiltInvertPitch)
                        input.pitch = a.pitch * sensitivity
                        input.roll = a.roll * sensitivity
                    }
                }
            }
        }

        onScreen.apply(to: &input, throttle: &throttle, sensitivity: sensitivity)
        input.throttle = throttle

        if settings.invertPitch { input.pitch = -input.pitch }
        input.pitch = clamp(input.pitch, -1, 1)
        input.roll = clamp(input.roll, -1, 1)
        input.throttle = throttle
        return input
    }
}
