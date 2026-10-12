// Port of FlightCore/AircraftSpec.swift and FlightModel.swift.
import { Vec3, Quat, Axis, Units, clamp, mix, smoothstep, rad, deg, wrap360, headingDelta, quatFromEuler } from './math'
import { Atmosphere, Terrain } from './environment'

export type AircraftKind = 'trainer' | 'fighter'
export type ContactKind = 'noseGear' | 'mainGear' | 'airframe'
export interface ContactPoint { name: string; position: Vec3; kind: ContactKind }

export interface AircraftSpec {
  kind: AircraftKind; name: string; shortName: string
  mass: number; inertia: Vec3; wingArea: number; wingSpan: number; chord: number
  cl0: number; clAlpha: number; stallAlpha: number; cd0: number; inducedDragK: number
  flapCL: number; flapCD: number; flapStallReduction: number; gearCD: number; cyBeta: number; cyRudder: number
  cm0: number; cmAlpha: number; cmQ: number; cmElevator: number; cmFlaps: number
  clBeta: number; clP: number; clR: number; clAileron: number
  cnBeta: number; cnR: number; cnRudder: number; cnAileron: number
  isJet: boolean; staticThrust: number; afterburnerThrust: number; propZeroThrustSpeed: number
  engineSpoolTime: number; propTurningTendency: number
  hasRetractableGear: boolean; flapDetents: number[]; flyByWire: boolean; gLimit: number
  alphaLimit: number; maxRollRate: number; trimRange: number
  contacts: ContactPoint[]; gearStiffness: number; gearDamping: number; maxSinkRate: number; noseSteerAngle: number
  vStallKt: number; vRotateKt: number; vClimbKt: number; vApproachKt: number; vCruiseKt: number; vNeKt: number
}

export const weightOf = (s: AircraftSpec) => s.mass * Units.g
export const stallAlphaOf = (s: AircraftSpec, flaps: number) => s.stallAlpha - s.flapStallReduction * flaps

const cp = (name: string, x: number, y: number, z: number, kind: ContactKind): ContactPoint => ({ name, position: new Vec3(x, y, z), kind })

/** A Cessna 172-like high-wing trainer. */
export const TRAINER: AircraftSpec = {
  kind: 'trainer', name: 'Skyhawk Trainer', shortName: 'Trainer',
  mass: 1000, inertia: new Vec3(1825, 2667, 1285), wingArea: 16.2, wingSpan: 11.0, chord: 1.5,
  cl0: 0.25, clAlpha: 4.8, stallAlpha: rad(15), cd0: 0.028, inducedDragK: 0.054,
  flapCL: 0.55, flapCD: 0.05, flapStallReduction: rad(2), gearCD: 0, cyBeta: -0.31, cyRudder: 0.06,
  cm0: 0, cmAlpha: -1.0, cmQ: -12.4, cmElevator: 0.55, cmFlaps: -0.04,
  clBeta: -0.089, clP: -0.47, clR: 0.096, clAileron: 0.045,
  cnBeta: 0.065, cnR: -0.099, cnRudder: 0.025, cnAileron: -0.006,
  isJet: false, staticThrust: 3000, afterburnerThrust: 0, propZeroThrustSpeed: 100,
  engineSpoolTime: 0.4, propTurningTendency: 420,
  hasRetractableGear: false, flapDetents: [0, 10, 20, 30], flyByWire: false, gLimit: 3.8,
  alphaLimit: 0, maxRollRate: 0, trimRange: 0.35,
  contacts: [
    cp('Nose wheel', 0, -1.3, -1.6, 'noseGear'), cp('Left main', -1.25, -1.3, 0.35, 'mainGear'),
    cp('Right main', 1.25, -1.3, 0.35, 'mainGear'), cp('Left wingtip', -5.5, 0.9, 0.3, 'airframe'),
    cp('Right wingtip', 5.5, 0.9, 0.3, 'airframe'), cp('Tail', 0, -0.2, 5.2, 'airframe'),
    cp('Propeller', 0, -0.85, -2.3, 'airframe'),
  ],
  gearStiffness: 36_000, gearDamping: 5_200, maxSinkRate: 4.0, noseSteerAngle: rad(25),
  vStallKt: 48, vRotateKt: 55, vClimbKt: 75, vApproachKt: 65, vCruiseKt: 115, vNeKt: 163,
}

/** An F/A-18-like twin-engine fighter with a simple fly-by-wire system. */
export const FIGHTER: AircraftSpec = {
  kind: 'fighter', name: 'Hornet Fighter', shortName: 'Fighter',
  mass: 16_000, inertia: new Vec3(205_000, 230_000, 31_000), wingArea: 38.0, wingSpan: 12.3, chord: 3.5,
  cl0: 0.05, clAlpha: 3.6, stallAlpha: rad(32), cd0: 0.022, inducedDragK: 0.12,
  flapCL: 0.5, flapCD: 0.04, flapStallReduction: 0, gearCD: 0.025, cyBeta: -0.8, cyRudder: 0.12,
  cm0: 0, cmAlpha: -0.45, cmQ: -6.0, cmElevator: 0.5, cmFlaps: -0.02,
  clBeta: -0.08, clP: -0.35, clR: 0.1, clAileron: 0.06,
  cnBeta: 0.12, cnR: -0.35, cnRudder: 0.045, cnAileron: -0.004,
  isJet: true, staticThrust: 110_000, afterburnerThrust: 158_000, propZeroThrustSpeed: 0,
  engineSpoolTime: 1.6, propTurningTendency: 0,
  hasRetractableGear: true, flapDetents: [0, 15, 30], flyByWire: true, gLimit: 7.5,
  alphaLimit: rad(25), maxRollRate: 3.5, trimRange: 0.25,
  contacts: [
    cp('Nose wheel', 0, -2.0, -5.5, 'noseGear'), cp('Left main', -1.6, -2.0, 0.8, 'mainGear'),
    cp('Right main', 1.6, -2.0, 0.8, 'mainGear'), cp('Left wingtip', -6.1, 0.0, 2.0, 'airframe'),
    cp('Right wingtip', 6.1, 0.0, 2.0, 'airframe'), cp('Tail', 0, -0.5, 7.8, 'airframe'),
    cp('Nose', 0, -0.6, -8.5, 'airframe'), cp('Belly', 0, -1.1, 0, 'airframe'),
  ],
  gearStiffness: 420_000, gearDamping: 60_000, maxSinkRate: 7.0, noseSteerAngle: rad(20),
  vStallKt: 110, vRotateKt: 150, vClimbKt: 350, vApproachKt: 155, vCruiseKt: 450, vNeKt: 750,
}

export const specOf = (k: AircraftKind) => (k === 'trainer' ? TRAINER : FIGHTER)

export class PilotInput {
  pitch = 0      // + = stick back (nose up)
  roll = 0       // + = stick right
  yaw = 0        // + = right rudder
  throttle = 0   // 0...1 (fighter: > 0.95 lights the afterburner)
  brakes = 0
  trigger = false
  clone() { return Object.assign(new PilotInput(), this) }
}

export interface SurfaceDeflection { elevator: number; aileron: number; rudder: number }

export class AircraftState {
  position = new Vec3()
  velocity = new Vec3()
  orientation = Quat.identity()
  angularVelocity = new Vec3()   // body axes (x = pitch-up, y = yaw-left, z = roll-left)
  engine = 0
  flaps = 0
  flapsTarget = 0
  gear = 1
  gearDown = true
  elevatorTrim = 0
  surfaces: SurfaceDeflection = { elevator: 0, aileron: 0, rudder: 0 }
  onGround = false
  wheelsOnGround = 0
  crashed = false
  crashReason: string | null = null
  loadFactor = 1
  health = 100

  get forward() { return this.orientation.act(Axis.forward) }
  get up() { return this.orientation.act(Axis.up) }
  get right() { return this.orientation.act(Axis.right) }
  get rollRate() { return -this.angularVelocity.z }
  get pitchRate() { return this.angularVelocity.x }
  get yawRate() { return -this.angularVelocity.y }
  get pitchDeg() { return deg(Math.asin(clamp(this.forward.y, -1, 1))) }
  get bankDeg() { const r = this.right, u = this.up; return deg(Math.atan2(-r.y, u.y)) }
  get headingDeg() {
    const f = this.forward
    if (Math.abs(f.y) > 0.99) { const u = this.up; return wrap360(deg(Math.atan2(-u.x * f.y, u.z * f.y))) }
    return wrap360(deg(Math.atan2(f.x, -f.z)))
  }
}

export interface AeroReadout {
  airspeed: number; alpha: number; beta: number; liftCoefficient: number
  dynamicPressure: number; thrust: number; stalled: boolean; stallMargin: number
}

export type TouchdownGrade = 'Greaser' | 'Good' | 'Firm' | 'Hard'
export interface TouchdownReport {
  sinkRateFpm: number; airspeedKt: number; centerlineOffset: number
  distanceFromThreshold: number; onRunway: boolean; bankDeg: number; grade: TouchdownGrade
}

export class Aircraft {
  state = new AircraftState()
  aero: AeroReadout = { airspeed: 0, alpha: 0, beta: 0, liftCoefficient: 0, dynamicPressure: 0, thrust: 0, stalled: false, stallMargin: 1 }
  autoRudder = true
  lastTouchdown: TouchdownReport | null = null
  touchdownCount = 0
  /** Heading captured while stopped on the ground; auto-rudder steers back to it on the roll. */
  private groundHeadingRef: number | null = null

  constructor(public spec: AircraftSpec) {}

  // MARK: Placement

  placeOnRunway(distanceFromSouthEnd = 60) {
    this.state = new AircraftState()
    const mains = this.spec.contacts.filter(c => c.kind === 'mainGear').map(c => c.position.y)
    const gearHeight = -(mains.length ? Math.min(...mains) : -1.3)
    this.state.position = new Vec3(0, gearHeight - 0.02, Terrain.runwaySouthEnd - distanceFromSouthEnd)
    this.state.orientation = quatFromEuler(0, this.groundPitchDeg, 0)
    this.state.onGround = true
    this.state.wheelsOnGround = 3
    this.lastTouchdown = null
  }

  get groundPitchDeg() {
    const nose = this.spec.contacts.find(c => c.kind === 'noseGear')
    const main = this.spec.contacts.find(c => c.kind === 'mainGear')
    if (!nose || !main) return 0
    return deg(Math.atan2(main.position.y - nose.position.y, main.position.z - nose.position.z))
  }

  placeInFlight(position: Vec3, headingDeg: number, airspeedKt: number, gearDown: boolean | null = null, flaps = 0) {
    const spec = this.spec
    this.state = new AircraftState()
    const v = airspeedKt * Units.knot
    const rho = Atmosphere.density(position.y)
    const cl = weightOf(spec) / Math.max(0.5 * rho * v * v * spec.wingArea, 1)
    const alpha = clamp((cl - spec.cl0 - spec.flapCL * flaps) / spec.clAlpha, -0.1, 0.25)
    const s = this.state
    s.position = position.clone()
    s.orientation = quatFromEuler(headingDeg, deg(alpha), 0)
    s.velocity = quatFromEuler(headingDeg, 0, 0).act(Axis.forward).mul(v)
    s.flaps = flaps
    s.flapsTarget = flaps
    s.gearDown = gearDown ?? !spec.hasRetractableGear
    s.gear = s.gearDown ? 1 : 0
    const cm = spec.cm0 + spec.cmAlpha * alpha + spec.cmFlaps * flaps
    s.elevatorTrim = clamp(-cm / spec.cmElevator, -spec.trimRange, spec.trimRange)
    const cd = spec.cd0 + spec.inducedDragK * cl * cl + spec.flapCD * flaps + (s.gearDown ? spec.gearCD : 0)
    const drag = 0.5 * rho * v * v * spec.wingArea * cd
    s.engine = clamp(this.throttleFor(drag, v, position.y), 0, 1)
    this.lastTouchdown = null
  }

  private throttleFor(thrust: number, v: number, altitude: number) {
    const rhoRatio = Atmosphere.density(altitude) / Atmosphere.seaLevelDensity
    if (this.spec.isJet) return thrust / (this.spec.staticThrust * rhoRatio)
    return thrust / (this.spec.staticThrust * rhoRatio * Math.max(0.05, 1 - v / this.spec.propZeroThrustSpeed))
  }

  // MARK: Systems

  setFlaps(delta: number) {
    const steps = this.spec.flapDetents.length - 1
    const current = Math.round(this.state.flapsTarget * steps)
    this.state.flapsTarget = clamp(current + delta, 0, steps) / steps
  }

  toggleGear() {
    if (!this.spec.hasRetractableGear) return
    if (this.state.wheelsOnGround > 0 && this.state.gearDown) return
    this.state.gearDown = !this.state.gearDown
  }

  adjustTrim(delta: number) {
    this.state.elevatorTrim = clamp(this.state.elevatorTrim + delta, -this.spec.trimRange, this.spec.trimRange)
  }

  // MARK: Physics

  step(dt: number, input: PilotInput, wind: Vec3) {
    const s = this.state
    if (s.crashed) return
    const spec = this.spec

    s.engine += (clamp(input.throttle, 0, 1) - s.engine) * Math.min(1, dt / spec.engineSpoolTime)
    s.flaps += clamp(s.flapsTarget - s.flaps, -0.25 * dt, 0.25 * dt)
    s.gear = clamp(s.gear + ((s.gearDown ? 1 : -1) * dt) / 4, 0, 1)

    const rho = Atmosphere.density(s.position.y)
    const vBody = s.orientation.inverse().act(s.velocity.sub(wind))
    const airspeed = vBody.length()
    const u = -vBody.z, v = vBody.x, w = vBody.y
    const alpha = airspeed > 0.5 ? Math.atan2(-w, u) : 0
    const beta = airspeed > 0.5 ? Math.asin(clamp(v / airspeed, -1, 1)) : 0
    const qbar = 0.5 * rho * airspeed * airspeed
    const vRef = Math.max(airspeed, 8)
    const p = s.rollRate, q = s.pitchRate, r = s.yawRate

    if (s.wheelsOnGround === 0) this.groundHeadingRef = null
    else if (this.groundHeadingRef === null || s.velocity.length() < 2 || Math.abs(input.yaw) > 0.05) this.groundHeadingRef = s.headingDeg

    s.surfaces = this.controlLaw(input, s, alpha, beta, airspeed)

    const agl = s.position.y - Terrain.height(s.position.x, s.position.z)
    const a0 = stallAlphaOf(spec, s.flaps)
    const cl = Aircraft.liftCoefficient(spec, alpha, s.flaps)
    const stallBlend = smoothstep(a0, a0 + rad(4), Math.abs(alpha))
    const hb = Math.max(agl, 0.1) / spec.wingSpan
    const groundEffect = hb < 1 ? (16 * hb * hb) / (1 + 16 * hb * hb) : 1
    let cd = spec.cd0 + spec.inducedDragK * Math.min(cl * cl, 4) * groundEffect
    cd += spec.flapCD * s.flaps + spec.gearCD * s.gear
    cd += 1.3 * Math.sin(alpha) ** 2 * smoothstep(a0, a0 + rad(10), Math.abs(alpha))
    cd += 0.6 * Math.sin(beta) ** 2
    const cy = spec.cyBeta * beta + spec.cyRudder * s.surfaces.rudder

    const pHat = (p * spec.wingSpan) / (2 * vRef)
    const qHat = (q * spec.chord) / (2 * vRef)
    const rHat = (r * spec.wingSpan) / (2 * vRef)
    const aileronEffect = 1 - 0.6 * stallBlend
    let cRoll = spec.clBeta * beta + spec.clP * pHat + spec.clR * rHat + spec.clAileron * s.surfaces.aileron * aileronEffect
    cRoll += stallBlend * 0.06 * clamp(r * 2 + beta * 3, -1, 1)
    const cm = spec.cm0 + spec.cmAlpha * clamp(alpha, -0.6, 0.6) + spec.cmQ * qHat
      + spec.cmElevator * s.surfaces.elevator + spec.cmFlaps * s.flaps
      - 0.25 * stallBlend * (alpha > 0 ? 1 : -1)
    const cn = spec.cnBeta * beta + spec.cnR * rHat + spec.cnRudder * s.surfaces.rudder + spec.cnAileron * s.surfaces.aileron

    let force = new Vec3()
    if (airspeed > 0.5) {
      const vHat = vBody.mul(1 / airspeed)
      const sym = new Vec3(0, vHat.y, vHat.z)
      const symLen = sym.length()
      const liftDir = symLen > 1e-6 ? Axis.right.cross(sym.mul(1 / symLen)).normalized() : Axis.up
      force = force.add(liftDir.mul(qbar * spec.wingArea * cl))
      force = force.add(vHat.mul(-qbar * spec.wingArea * cd))
      force = force.add(Axis.right.mul(qbar * spec.wingArea * cy))
    }

    const rhoRatio = rho / Atmosphere.seaLevelDensity
    let thrust: number
    if (spec.isJet) {
      const military = Math.min(s.engine / 0.95, 1)
      const burner = smoothstep(0.95, 1.0, s.engine)
      thrust = (spec.staticThrust * military + (spec.afterburnerThrust - spec.staticThrust) * burner) * rhoRatio
    } else {
      thrust = spec.staticThrust * s.engine * rhoRatio * Math.max(0, 1 - Math.max(u, 0) / spec.propZeroThrustSpeed)
    }
    force = force.add(Axis.forward.mul(thrust))

    let torque = new Vec3(qbar * spec.wingArea * spec.chord * cm, -qbar * spec.wingArea * spec.wingSpan * cn, -qbar * spec.wingArea * spec.wingSpan * cRoll)
    if (spec.propTurningTendency > 0) {
      torque.y += spec.propTurningTendency * s.engine * Math.max(0.2, 1 - airspeed / 70)
    }

    let worldForce = s.orientation.act(force)
    const ground = this.groundForces(s, input.brakes, input.yaw)
    worldForce = worldForce.add(ground.force)
    torque = torque.add(s.orientation.inverse().act(ground.torque))
    s.loadFactor = worldForce.dot(s.up) / weightOf(spec)
    worldForce = worldForce.add(new Vec3(0, -weightOf(spec), 0))

    s.velocity = s.velocity.add(worldForce.mul(dt / spec.mass))
    s.position = s.position.add(s.velocity.mul(dt))

    const I = spec.inertia
    const omega = s.angularVelocity
    const omegaDot = torque.sub(omega.cross(I.hadamard(omega))).divv(I)
    s.angularVelocity = omega.add(omegaDot.mul(dt))
    if (s.wheelsOnGround > 0) s.angularVelocity = s.angularVelocity.mul(0.999)
    const av = s.angularVelocity
    const dq = s.orientation.mul(new Quat(av.x, av.y, av.z, 0))
    const o = s.orientation, h = 0.5 * dt
    s.orientation = new Quat(o.x + dq.x * h, o.y + dq.y * h, o.z + dq.z * h, o.w + dq.w * h).normalized()

    if (!s.crashed && s.position.y < Terrain.height(s.position.x, s.position.z) - 0.5) this.crash(s, 'Flew into the ground')

    this.aero = {
      airspeed, alpha, beta, liftCoefficient: cl, dynamicPressure: qbar, thrust,
      stalled: Math.abs(alpha) > a0, stallMargin: clamp(1 - alpha / a0, 0, 1),
    }
  }

  static liftCoefficient(spec: AircraftSpec, alpha: number, flaps: number) {
    const a0 = stallAlphaOf(spec, flaps)
    const dFlap = spec.flapCL * flaps
    const negStall = -a0 * 0.8
    const linear = spec.cl0 + spec.clAlpha * alpha + dFlap
    if (alpha <= a0 && alpha >= negStall) return linear
    const edge = alpha > 0 ? a0 : negStall
    const peak = spec.cl0 + spec.clAlpha * edge + dFlap
    const over = Math.abs(alpha - edge)
    const flatPlate = 1.1 * Math.sin(2 * alpha)
    const afterBreak = peak * (1 - 0.3 * smoothstep(0, rad(4), over))
    return mix(afterBreak, flatPlate, smoothstep(rad(4), rad(20), over))
  }

  private controlLaw(input: PilotInput, s: AircraftState, alpha: number, beta: number, airspeed: number): SurfaceDeflection {
    const spec = this.spec
    const airborne = s.wheelsOnGround === 0
    if (spec.flyByWire && airborne && airspeed > 40) {
      let e = input.pitch + s.elevatorTrim - 0.35 * s.pitchRate
      e -= 2.0 * Math.max(0, s.loadFactor - (spec.gLimit - 0.4))
      e += 0.4 * Math.max(0, -3 - s.loadFactor)
      e -= 2.5 * Math.max(0, alpha - spec.alphaLimit)
      return {
        elevator: clamp(e, -1, 1),
        aileron: clamp((input.roll * spec.maxRollRate - s.rollRate) * 0.5, -1, 1),
        rudder: clamp(input.yaw + 2.0 * beta - 0.15 * s.yawRate, -1, 1),
      }
    }
    let rudder = input.yaw
    if (this.autoRudder && !airborne) {
      const propYaw = spec.propTurningTendency > 0 ? 0.3 * s.engine * Math.max(0.2, 1 - airspeed / 70) : 0
      const headingError = headingDelta(this.groundHeadingRef ?? s.headingDeg, s.headingDeg)
      rudder += clamp(propYaw + 0.08 * headingError - 12 * s.yawRate, -0.7, 0.7)
    }
    if (this.autoRudder && airborne) {
      rudder += clamp(3.0 * beta, -0.8, 0.8)
      if (spec.propTurningTendency > 0) {
        const rho = Atmosphere.density(s.position.y)
        const vv = Math.max(airspeed, 15)
        const perRudder = 0.5 * rho * vv * vv * spec.wingArea * spec.wingSpan * spec.cnRudder
        const propYaw = spec.propTurningTendency * s.engine * Math.max(0.2, 1 - airspeed / 70)
        rudder += clamp(propYaw / perRudder, 0, 0.6)
      }
    }
    return { elevator: clamp(input.pitch + s.elevatorTrim, -1, 1), aileron: clamp(input.roll, -1, 1), rudder: clamp(rudder, -1, 1) }
  }

  // MARK: Ground

  private groundForces(s: AircraftState, brakes: number, rudder: number) {
    const result = { force: new Vec3(), torque: new Vec3() }
    const spec = this.spec
    let wheels = 0
    const wasOnGround = s.wheelsOnGround > 0
    let touchdownSink = 0

    for (const contact of spec.contacts) {
      const isGear = contact.kind !== 'airframe'
      if (isGear && s.gear < 0.98) continue
      const arm = s.orientation.act(contact.position)
      const p = s.position.add(arm)
      const depth = Terrain.height(p.x, p.z) - p.y
      if (!(depth > 0)) continue

      const omegaWorld = s.orientation.act(s.angularVelocity)
      const pointVel = s.velocity.add(omegaWorld.cross(arm))

      if (!isGear) { this.crash(s, `${contact.name} hit the ground`); return result }
      if (-pointVel.y > spec.maxSinkRate) {
        this.crash(s, `Hard landing: ${Math.round(-pointVel.y / Units.feetPerMinute)} fpm on the ${contact.name.toLowerCase()}`)
        return result
      }
      touchdownSink = Math.max(touchdownSink, -pointVel.y)
      wheels += 1

      const n = Terrain.normal(p.x, p.z)
      const normalSpeed = pointVel.dot(n)
      const share = contact.kind === 'noseGear' ? 0.6 : 1.0
      const normalForce = Math.max(0, spec.gearStiffness * share * depth - spec.gearDamping * share * normalSpeed)
      let f = n.mul(normalForce)

      const fwd = s.forward
      let rollDir = fwd.sub(n.mul(fwd.dot(n)))
      if (contact.kind === 'noseGear') {
        const steer = -rudder * spec.noseSteerAngle * clamp(1 - s.velocity.length() / 40, 0.15, 1)
        rollDir = Quat.fromAxisAngle(steer, n).act(rollDir)
      }
      rollDir = rollDir.normalized()
      const sideDir = rollDir.cross(n)
      const tangentVel = pointVel.sub(n.mul(normalSpeed))
      const vRoll = tangentVel.dot(rollDir)
      const vSide = tangentVel.dot(sideDir)
      const rolling = Terrain.isOnRunway(p.x, p.z) ? 0.015 : 0.05
      const brake = contact.kind === 'mainGear' ? brakes * 0.55 : 0
      const longForce = -clamp(vRoll * 4, -1, 1) * (rolling + brake) * normalForce
      const sideForce = -clamp(vSide * 5, -1, 1) * 0.8 * normalForce
      f = f.add(rollDir.mul(longForce)).add(sideDir.mul(sideForce))

      result.force = result.force.add(f)
      result.torque = result.torque.add(arm.cross(f))
    }

    s.wheelsOnGround = wheels
    s.onGround = wheels > 0
    if (wheels > 0 && !wasOnGround) this.recordTouchdown(s, touchdownSink)
    return result
  }

  private recordTouchdown(s: AircraftState, sink: number) {
    this.touchdownCount += 1
    const fpm = sink / Units.feetPerMinute
    const grade: TouchdownGrade = fpm < 150 ? 'Greaser' : fpm < 350 ? 'Good' : fpm < 600 ? 'Firm' : 'Hard'
    const horiz = s.velocity
    this.lastTouchdown = {
      sinkRateFpm: fpm, airspeedKt: horiz.length() / Units.knot, centerlineOffset: s.position.x,
      distanceFromThreshold: Terrain.runwaySouthEnd - s.position.z,
      onRunway: Terrain.isOnRunway(s.position.x, s.position.z), bankDeg: s.bankDeg, grade,
    }
  }

  crash(s: AircraftState, reason: string) {
    s.crashed = true
    s.crashReason = reason
    s.velocity = new Vec3()
    s.angularVelocity = new Vec3()
  }
}
