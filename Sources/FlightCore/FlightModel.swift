import Foundation
import simd

/// What the pilot is asking for. Stick axes are -1...1.
public struct PilotInput: Equatable {
    public var pitch: Double = 0      // + = stick back (nose up)
    public var roll: Double = 0       // + = stick right
    public var yaw: Double = 0        // + = right rudder
    public var throttle: Double = 0   // 0...1 (fighter: > 0.95 lights the afterburner)
    public var brakes: Double = 0     // 0...1
    public var trigger = false
    public init() {}
}

/// Normalised control-surface deflections actually applied (after fly-by-wire / auto-rudder).
public struct SurfaceDeflection: Equatable {
    public var elevator: Double = 0
    public var aileron: Double = 0
    public var rudder: Double = 0
}

/// Full rigid-body state of one aircraft.
public struct AircraftState {
    public var position = Vec3.zero                 // world, metres
    public var velocity = Vec3.zero                 // world, m/s
    public var orientation = Quat.identity          // body → world
    public var angularVelocity = Vec3.zero          // body axes (x = pitch-up, y = yaw-left, z = roll-left)

    public var engine = 0.0                         // spooled throttle 0...1
    public var flaps = 0.0                          // actual flap position 0...1
    public var flapsTarget = 0.0
    public var gear = 1.0                           // 1 = down and locked
    public var gearDown = true
    public var elevatorTrim = 0.0
    public var surfaces = SurfaceDeflection()

    public var onGround = false
    public var wheelsOnGround = 0
    public var crashed = false
    public var crashReason: String?
    public var loadFactor = 1.0                     // g along body up
    public var health = 100.0

    public init() {}

    // Body axes in world coordinates
    public var forward: Vec3 { orientation.act(Axis.forward) }
    public var up: Vec3 { orientation.act(Axis.up) }
    public var right: Vec3 { orientation.act(Axis.right) }

    /// Conventional body rates (rad/s): roll right +, pitch up +, yaw right +.
    public var rollRate: Double { -angularVelocity.z }
    public var pitchRate: Double { angularVelocity.x }
    public var yawRate: Double { -angularVelocity.y }

    public var pitchDeg: Double { asin(clamp(forward.y, -1, 1)).degrees }
    public var bankDeg: Double { atan2(-right.y, up.y).degrees }
    public var headingDeg: Double {
        let f = forward
        // When pointing straight up/down use the up vector's horizontal direction instead.
        if abs(f.y) > 0.99 { return wrap360(atan2(-up.x * f.y, up.z * f.y).degrees) }
        return wrap360(atan2(f.x, -f.z).degrees)
    }
}

/// Aerodynamic quantities from the latest step, for instruments and the instructor.
public struct AeroReadout {
    public var airspeed = 0.0       // true airspeed m/s
    public var alpha = 0.0          // rad
    public var beta = 0.0           // rad (+ = relative wind from the right)
    public var liftCoefficient = 0.0
    public var dynamicPressure = 0.0
    public var thrust = 0.0
    public var stalled = false
    public var stallMargin = 1.0    // 0 at stall alpha, 1 at zero alpha
}

public enum TouchdownGrade: String {
    case greaser = "Greaser"
    case good = "Good"
    case firm = "Firm"
    case hard = "Hard"
}

public struct TouchdownReport: Equatable {
    public var sinkRateFpm: Double
    public var airspeedKt: Double
    public var centerlineOffset: Double   // metres, + = right of centreline
    public var distanceFromThreshold: Double
    public var onRunway: Bool
    public var bankDeg: Double
    public var grade: TouchdownGrade
}

/// One simulated aircraft: spec + state + the physics step.
public struct Aircraft {
    public var spec: AircraftSpec
    public var state = AircraftState()
    public var aero = AeroReadout()
    public var autoRudder = true
    public var lastTouchdown: TouchdownReport?
    /// Heading captured while stopped on the ground; auto-rudder steers back to it on the roll.
    var groundHeadingRef: Double?
    public private(set) var touchdownCount = 0

    public init(spec: AircraftSpec) {
        self.spec = spec
    }

    // MARK: Placement

    /// Sits the aircraft on the runway 36 threshold, engine idle, brakes ready.
    public mutating func placeOnRunway(distanceFromSouthEnd: Double = 60) {
        state = AircraftState()
        let gearHeight = -(spec.contacts.filter { $0.kind == .mainGear }.map { $0.position.y }.min() ?? -1.3)
        state.position = Vec3(0, gearHeight - 0.02, Terrain.runwaySouthEnd - distanceFromSouthEnd)
        state.orientation = .fromEuler(headingDeg: 0, pitchDeg: groundPitchDeg, bankDeg: 0)
        state.onGround = true
        state.wheelsOnGround = 3
        lastTouchdown = nil
    }

    /// Nose attitude when all wheels touch the ground.
    var groundPitchDeg: Double {
        guard let nose = spec.contacts.first(where: { $0.kind == .noseGear }),
              let main = spec.contacts.first(where: { $0.kind == .mainGear }) else { return 0 }
        return atan2(main.position.y - nose.position.y, main.position.z - nose.position.z).degrees
    }

    /// Puts the aircraft in steady flight at the given position, heading and airspeed.
    public mutating func placeInFlight(position: Vec3, headingDeg: Double, airspeedKt: Double, gearDown: Bool? = nil, flaps: Double = 0) {
        state = AircraftState()
        let v = airspeedKt * Units.knot
        let rho = Atmosphere.density(altitude: position.y)
        let cl = spec.weight / max(0.5 * rho * v * v * spec.wingArea, 1)
        let alpha = clamp((cl - spec.cl0 - spec.flapCL * flaps) / spec.clAlpha, -0.1, 0.25)
        state.position = position
        state.orientation = .fromEuler(headingDeg: headingDeg, pitchDeg: alpha.degrees, bankDeg: 0)
        let dir = Quat.fromEuler(headingDeg: headingDeg, pitchDeg: 0, bankDeg: 0).act(Axis.forward)
        state.velocity = dir * v
        state.flaps = flaps
        state.flapsTarget = flaps
        state.gearDown = gearDown ?? !spec.hasRetractableGear
        state.gear = state.gearDown ? 1 : 0
        // Trim elevator so the pitching moment is zero at this alpha, and set cruise-ish power.
        let cm = spec.cm0 + spec.cmAlpha * alpha + spec.cmFlaps * flaps
        state.elevatorTrim = clamp(-cm / spec.cmElevator, -spec.trimRange, spec.trimRange)
        let cd = spec.cd0 + spec.inducedDragK * cl * cl + spec.flapCD * flaps + (state.gearDown ? spec.gearCD : 0)
        let drag = 0.5 * rho * v * v * spec.wingArea * cd
        state.engine = clamp(throttleFor(thrust: drag, airspeed: v, altitude: position.y), 0, 1)
        lastTouchdown = nil
    }

    func throttleFor(thrust: Double, airspeed v: Double, altitude: Double) -> Double {
        let rhoRatio = Atmosphere.density(altitude: altitude) / Atmosphere.seaLevelDensity
        if spec.isJet { return thrust / (spec.staticThrust * rhoRatio) }
        let perThrottle = spec.staticThrust * rhoRatio * max(0.05, 1 - v / spec.propZeroThrustSpeed)
        return thrust / perThrottle
    }

    // MARK: Systems

    public mutating func setFlaps(step delta: Int) {
        let steps = Double(spec.flapDetents.count - 1)
        let current = (state.flapsTarget * steps).rounded()
        state.flapsTarget = clamp(current + Double(delta), 0, steps) / steps
    }

    public mutating func toggleGear() {
        guard spec.hasRetractableGear else { return }
        if state.wheelsOnGround > 0 && state.gearDown { return } // squat switch
        state.gearDown.toggle()
    }

    public mutating func adjustTrim(_ delta: Double) {
        state.elevatorTrim = clamp(state.elevatorTrim + delta, -spec.trimRange, spec.trimRange)
    }

    // MARK: Physics

    /// Advances the aircraft by dt seconds (call with dt ≈ 1/240).
    public mutating func step(dt: Double, input: PilotInput, wind: Vec3) {
        guard !state.crashed else { return }
        let spec = self.spec
        var s = state

        // Engine and systems
        let throttle = clamp(input.throttle, 0, 1)
        s.engine += (throttle - s.engine) * min(1, dt / spec.engineSpoolTime)
        s.flaps += clamp(s.flapsTarget - s.flaps, -0.25 * dt, 0.25 * dt)
        s.gear = clamp(s.gear + (s.gearDown ? 1 : -1) * dt / 4, 0, 1)

        // Air-relative velocity in body axes
        let rho = Atmosphere.density(altitude: s.position.y)
        let airWorld = s.velocity - wind
        let vBody = s.orientation.inverse.act(airWorld)
        let airspeed = simd_length(vBody)
        let u = -vBody.z, v = vBody.x, w = vBody.y
        let alpha = airspeed > 0.5 ? atan2(-w, u) : 0
        let beta = airspeed > 0.5 ? asin(clamp(v / airspeed, -1, 1)) : 0
        let qbar = 0.5 * rho * airspeed * airspeed
        let vRef = max(airspeed, 8)
        let p = s.rollRate, q = s.pitchRate, r = s.yawRate

        if s.wheelsOnGround == 0 { groundHeadingRef = nil }
        else if groundHeadingRef == nil || simd_length(s.velocity) < 2 || abs(input.yaw) > 0.05 { groundHeadingRef = s.headingDeg }

        // Controls: fly-by-wire or direct, plus optional auto-rudder.
        s.surfaces = controlLaw(input: input, state: s, alpha: alpha, beta: beta, airspeed: airspeed)

        // Coefficients
        let agl = s.position.y - Terrain.height(x: s.position.x, z: s.position.z)
        let a0 = spec.stallAlpha(flaps: s.flaps)
        let cl = Aircraft.liftCoefficient(spec: spec, alpha: alpha, flaps: s.flaps)
        let stallBlend = smoothstep(a0, a0 + 4.radians, abs(alpha))
        let hb = max(agl, 0.1) / spec.wingSpan
        let groundEffect = hb < 1 ? (16 * hb * hb) / (1 + 16 * hb * hb) : 1
        var cd = spec.cd0 + spec.inducedDragK * min(cl * cl, 4) * groundEffect
        cd += spec.flapCD * s.flaps + spec.gearCD * s.gear
        cd += 1.3 * pow(sin(alpha), 2) * smoothstep(a0, a0 + 10.radians, abs(alpha))
        cd += 0.6 * pow(sin(beta), 2)
        let cy = spec.cyBeta * beta + spec.cyRudder * s.surfaces.rudder

        let pHat = p * spec.wingSpan / (2 * vRef)
        let qHat = q * spec.chord / (2 * vRef)
        let rHat = r * spec.wingSpan / (2 * vRef)
        // Ailerons lose bite in a stall; a stalled wing drops toward the side you're slipping/yawing to.
        let aileronEffect = 1 - 0.6 * stallBlend
        var cRoll = spec.clBeta * beta + spec.clP * pHat + spec.clR * rHat + spec.clAileron * s.surfaces.aileron * aileronEffect
        cRoll += stallBlend * 0.06 * clamp(r * 2 + beta * 3, -1, 1)
        let cm = spec.cm0 + spec.cmAlpha * clamp(alpha, -0.6, 0.6) + spec.cmQ * qHat
            + spec.cmElevator * s.surfaces.elevator + spec.cmFlaps * s.flaps
            - 0.25 * stallBlend * (alpha > 0 ? 1 : -1)  // nose drops when stalled
        let cn = spec.cnBeta * beta + spec.cnR * rHat + spec.cnRudder * s.surfaces.rudder + spec.cnAileron * s.surfaces.aileron

        // Aero forces in body axes
        var force = Vec3.zero
        if airspeed > 0.5 {
            let vHat = vBody / airspeed
            let dragDir = -vHat
            // Lift is perpendicular to the airflow within the plane of symmetry.
            var sym = vHat; sym.x = 0
            let symLen = simd_length(sym)
            let liftDir = symLen > 1e-6 ? simd_normalize(simd_cross(Axis.right, sym / symLen)) : Axis.up
            force += liftDir * (qbar * spec.wingArea * cl)
            force += dragDir * (qbar * spec.wingArea * cd)
            force += Axis.right * (qbar * spec.wingArea * cy)
        }

        // Thrust
        let rhoRatio = rho / Atmosphere.seaLevelDensity
        var thrust: Double
        if spec.isJet {
            let military = min(s.engine / 0.95, 1)
            let burner = smoothstep(0.95, 1.0, s.engine)
            thrust = (spec.staticThrust * military + (spec.afterburnerThrust - spec.staticThrust) * burner) * rhoRatio
        } else {
            thrust = spec.staticThrust * s.engine * rhoRatio * max(0, 1 - max(u, 0) / spec.propZeroThrustSpeed)
        }
        force += Axis.forward * thrust

        // Aero moments → body torque. Body x = pitch up, y = yaw left, z = roll left.
        let span = spec.wingSpan, chord = spec.chord, area = spec.wingArea
        var torque = Vec3(qbar * area * chord * cm,
                          -qbar * area * span * cn,
                          -qbar * area * span * cRoll)
        // Propeller left-turning tendency (torque + P-factor), strongest at high power / low speed.
        if spec.propTurningTendency > 0 {
            let factor = s.engine * max(0.2, 1 - airspeed / 70)
            torque.y += spec.propTurningTendency * factor          // yaw left
        }

        // Load factor is everything except gravity, along body up.
        var worldForce = s.orientation.act(force)

        // Ground contact
        let ground = groundForces(state: &s, brakes: input.brakes, rudder: input.yaw, dt: dt)
        worldForce += ground.force
        torque += s.orientation.inverse.act(ground.torque)
        s.loadFactor = simd_dot(worldForce, s.up) / spec.weight

        worldForce += Vec3(0, -spec.weight, 0)

        // Integrate (semi-implicit Euler)
        let accel = worldForce / spec.mass
        s.velocity += accel * dt
        s.position += s.velocity * dt

        let I = spec.inertia
        let omega = s.angularVelocity
        let omegaDot = (torque - simd_cross(omega, I * omega)) / I
        s.angularVelocity += omegaDot * dt
        if s.wheelsOnGround > 0 { s.angularVelocity *= 0.999 }
        let spin = Quat(ix: s.angularVelocity.x, iy: s.angularVelocity.y, iz: s.angularVelocity.z, r: 0)
        let dq = s.orientation * spin
        s.orientation = Quat(vector: s.orientation.vector + dq.vector * (0.5 * dt)).normalized

        if !s.crashed {
            checkTerrainCollision(&s)
        }

        aero = AeroReadout(airspeed: airspeed, alpha: alpha, beta: beta, liftCoefficient: cl,
                           dynamicPressure: qbar, thrust: thrust,
                           stalled: abs(alpha) > a0,
                           stallMargin: clamp(1 - alpha / a0, 0, 1))
        state = s
    }

    /// Lift coefficient with a linear range, a stall break, and flat-plate behaviour at high alpha.
    public static func liftCoefficient(spec: AircraftSpec, alpha: Double, flaps: Double) -> Double {
        let a0 = spec.stallAlpha(flaps: flaps)
        let dFlap = spec.flapCL * flaps
        let negStall = -a0 * 0.8
        let linear = spec.cl0 + spec.clAlpha * alpha + dFlap
        if alpha <= a0 && alpha >= negStall { return linear }
        let edge = alpha > 0 ? a0 : negStall
        let peak = spec.cl0 + spec.clAlpha * edge + dFlap
        let over = abs(alpha - edge)
        let flatPlate = 1.1 * sin(2 * alpha)
        let afterBreak = peak * (1 - 0.3 * smoothstep(0, 4.radians, over))
        return mix(afterBreak, flatPlate, smoothstep(4.radians, 20.radians, over))
    }

    func controlLaw(input: PilotInput, state s: AircraftState, alpha: Double, beta: Double, airspeed: Double) -> SurfaceDeflection {
        var out = SurfaceDeflection()
        let airborne = s.wheelsOnGround == 0
        if spec.flyByWire && airborne && airspeed > 40 {
            // Pitch: stick commands nose motion; damper, g-limiter and alpha-limiter on top.
            var e = input.pitch + s.elevatorTrim - 0.35 * s.pitchRate
            e -= 2.0 * max(0, s.loadFactor - (spec.gLimit - 0.4))
            e += 0.4 * max(0, -3 - s.loadFactor)
            e -= 2.5 * max(0, alpha - spec.alphaLimit)
            out.elevator = clamp(e, -1, 1)
            // Roll: stick commands roll rate.
            out.aileron = clamp((input.roll * spec.maxRollRate - s.rollRate) * 0.5, -1, 1)
            // Yaw: pedals plus yaw damper and turn coordination.
            out.rudder = clamp(input.yaw + 2.0 * beta - 0.15 * s.yawRate, -1, 1)
        } else {
            out.elevator = clamp(input.pitch + s.elevatorTrim, -1, 1)
            out.aileron = clamp(input.roll, -1, 1)
            var rudder = input.yaw
            if autoRudder && !airborne {
                // On the ground, auto-rudder steers against any yaw rate (keeps you straight on the roll).
                // Holds the heading the takeoff roll started on and counters the propeller's yaw.
                let propYaw = spec.propTurningTendency > 0 ? 0.3 * s.engine * max(0.2, 1 - airspeed / 70) : 0
                let headingError = headingDelta(groundHeadingRef ?? s.headingDeg, s.headingDeg)
                rudder += clamp(propYaw + 0.08 * headingError - 12 * s.yawRate, -0.7, 0.7)
            }
            if autoRudder && airborne {
                // Auto-coordination: rudder against sideslip, plus counter the prop's left-turning tendency.
                rudder += clamp(3.0 * beta, -0.8, 0.8)
                if spec.propTurningTendency > 0 {
                    let rho = Atmosphere.density(altitude: s.position.y)
                    let perRudder = 0.5 * rho * max(airspeed, 15) * max(airspeed, 15) * spec.wingArea * spec.wingSpan * spec.cnRudder
                    let propYaw = spec.propTurningTendency * s.engine * max(0.2, 1 - airspeed / 70)
                    rudder += clamp(propYaw / perRudder, 0, 0.6)
                }
            }
            out.rudder = clamp(rudder, -1, 1)
        }
        return out
    }

    // MARK: Ground

    struct GroundResult { var force = Vec3.zero; var torque = Vec3.zero }

    mutating func groundForces(state s: inout AircraftState, brakes: Double, rudder: Double, dt: Double) -> GroundResult {
        var result = GroundResult()
        var wheels = 0
        let wasOnGround = s.wheelsOnGround > 0
        var touchdownSink = 0.0

        for contact in spec.contacts {
            let isGear = contact.kind != .airframe
            if isGear && s.gear < 0.98 { continue }
            let arm = s.orientation.act(contact.position)
            let p = s.position + arm
            let groundY = Terrain.height(x: p.x, z: p.z)
            let depth = groundY - p.y
            guard depth > 0 else { continue }

            let omegaWorld = s.orientation.act(s.angularVelocity)
            let pointVel = s.velocity + simd_cross(omegaWorld, arm)

            if !isGear {
                crash(&s, "\(contact.name) hit the ground")
                return result
            }
            if -pointVel.y > spec.maxSinkRate {
                crash(&s, String(format: "Hard landing: %.0f fpm on the %@", -pointVel.y / Units.feetPerMinute, contact.name.lowercased()))
                return result
            }
            touchdownSink = max(touchdownSink, -pointVel.y)
            wheels += 1

            let n = Terrain.normal(x: p.x, z: p.z)
            let normalSpeed = simd_dot(pointVel, n)
            let share = contact.kind == .noseGear ? 0.6 : 1.0
            let normalForce = max(0, spec.gearStiffness * share * depth - spec.gearDamping * share * normalSpeed)
            var f = n * normalForce

            // Wheel direction: aircraft forward projected on the ground, nose wheel steered by the rudder pedals.
            var rollDir = s.forward - n * simd_dot(s.forward, n)
            if contact.kind == .noseGear {
                let steer = -rudder * spec.noseSteerAngle * clamp(1 - simd_length(s.velocity) / 40, 0.15, 1)
                rollDir = simd_quatd(angle: steer, axis: n).act(rollDir)
            }
            rollDir = simd_normalize(rollDir)
            let sideDir = simd_cross(rollDir, n)
            let tangentVel = pointVel - n * normalSpeed
            let vRoll = simd_dot(tangentVel, rollDir)
            let vSide = simd_dot(tangentVel, sideDir)
            let onPavement = Terrain.isOnRunway(x: p.x, z: p.z)
            let rolling = onPavement ? 0.015 : 0.05
            let brake = contact.kind == .mainGear ? brakes * 0.55 : 0
            let mu = rolling + brake
            let longForce = -clamp(vRoll * 4, -1, 1) * mu * normalForce
            let sideForce = -clamp(vSide * 5, -1, 1) * 0.8 * normalForce
            f += rollDir * longForce + sideDir * sideForce

            result.force += f
            result.torque += simd_cross(arm, f)
        }

        s.wheelsOnGround = wheels
        s.onGround = wheels > 0
        if wheels > 0 && !wasOnGround {
            recordTouchdown(s, sink: touchdownSink)
        }
        return result
    }

    mutating func recordTouchdown(_ s: AircraftState, sink: Double) {
        touchdownCount += 1
        let fpm = sink / Units.feetPerMinute
        let grade: TouchdownGrade = fpm < 150 ? .greaser : fpm < 350 ? .good : fpm < 600 ? .firm : .hard
        lastTouchdown = TouchdownReport(
            sinkRateFpm: fpm,
            airspeedKt: simd_length(s.velocity) / Units.knot,
            centerlineOffset: s.position.x,
            distanceFromThreshold: Terrain.runwaySouthEnd - s.position.z,
            onRunway: Terrain.isOnRunway(x: s.position.x, z: s.position.z),
            bankDeg: s.bankDeg,
            grade: grade)
    }

    func checkTerrainCollision(_ s: inout AircraftState) {
        // Catch-all for fast impacts that skip past contact points between steps.
        let ground = Terrain.height(x: s.position.x, z: s.position.z)
        if s.position.y < ground - 0.5 { crash(&s, "Flew into the ground") }
    }

    func crash(_ s: inout AircraftState, _ reason: String) {
        s.crashed = true
        s.crashReason = reason
        s.velocity = .zero
        s.angularVelocity = .zero
    }
}
