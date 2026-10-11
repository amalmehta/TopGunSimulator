import Foundation
import simd

/// A flat snapshot of everything a pilot (or the instruments, lessons and instructor) can read.
/// Values are in cockpit units: knots, feet, feet per minute, degrees.
public struct Telemetry: Equatable {
    public var time = 0.0
    public var airspeedKt = 0.0
    public var groundSpeedKt = 0.0
    public var altitudeFt = 0.0
    public var aglFt = 0.0
    public var verticalSpeedFpm = 0.0
    public var pitchDeg = 0.0
    public var bankDeg = 0.0
    public var headingDeg = 0.0
    public var trackDeg = 0.0
    public var alphaDeg = 0.0
    public var slipDeg = 0.0
    public var turnRateDegPerSec = 0.0
    public var gLoad = 1.0
    public var throttle = 0.0
    public var engine = 0.0
    public var flapsDeg = 0.0
    public var gearDown = true
    public var trim = 0.0
    public var brakes = 0.0
    public var onGround = false
    public var onRunway = false
    public var crashed = false
    public var crashReason: String?
    public var stalled = false
    public var stallMargin = 1.0
    public var afterburner = false
    public var position = Vec3.zero
    public var health = 100.0
    public var stickPitch = 0.0
    public var stickRoll = 0.0
    public var rudder = 0.0
    public var elevator = 0.0
    public var aileron = 0.0
    public var rudderSurface = 0.0

    public init() {}

    public init(aircraft a: Aircraft, input: PilotInput, time: Double) {
        let s = a.state
        self.time = time
        airspeedKt = a.aero.airspeed / Units.knot
        let horiz = Vec3(s.velocity.x, 0, s.velocity.z)
        groundSpeedKt = simd_length(horiz) / Units.knot
        altitudeFt = s.position.y / Units.foot
        aglFt = (s.position.y - Terrain.height(x: s.position.x, z: s.position.z)) / Units.foot
        verticalSpeedFpm = s.velocity.y / Units.feetPerMinute
        pitchDeg = s.pitchDeg
        bankDeg = s.bankDeg
        headingDeg = s.headingDeg
        trackDeg = simd_length(horiz) > 1 ? wrap360(atan2(horiz.x, -horiz.z).degrees) : s.headingDeg
        alphaDeg = a.aero.alpha.degrees
        slipDeg = a.aero.beta.degrees
        // Rate of change of heading ≈ yaw rate about the world vertical.
        let omegaWorld = s.orientation.act(s.angularVelocity)
        turnRateDegPerSec = -omegaWorld.y.degrees
        gLoad = s.loadFactor
        throttle = input.throttle
        engine = s.engine
        let detents = a.spec.flapDetents
        flapsDeg = s.flaps * (detents.last ?? 0)
        gearDown = s.gearDown
        trim = s.elevatorTrim
        brakes = input.brakes
        onGround = s.onGround
        onRunway = s.onGround && Terrain.isOnRunway(x: s.position.x, z: s.position.z)
        crashed = s.crashed
        crashReason = s.crashReason
        stalled = a.aero.stalled && !s.onGround
        stallMargin = a.aero.stallMargin
        afterburner = a.spec.isJet && s.engine > 0.95
        position = s.position
        health = s.health
        stickPitch = input.pitch
        stickRoll = input.roll
        rudder = input.yaw
        elevator = s.surfaces.elevator
        aileron = s.surfaces.aileron
        rudderSurface = s.surfaces.rudder
    }
}
