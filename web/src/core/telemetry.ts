// Port of FlightCore/Telemetry.swift: cockpit-unit snapshot (knots, feet, fpm, degrees).
import { Vec3, Units, deg, wrap360 } from './math'
import { Terrain } from './environment'
import { Aircraft, PilotInput } from './aircraft'

export interface Telemetry {
  time: number; airspeedKt: number; groundSpeedKt: number; altitudeFt: number; aglFt: number
  verticalSpeedFpm: number; pitchDeg: number; bankDeg: number; headingDeg: number; trackDeg: number
  alphaDeg: number; slipDeg: number; turnRateDegPerSec: number; gLoad: number; throttle: number
  engine: number; flapsDeg: number; gearDown: boolean; trim: number; brakes: number
  onGround: boolean; onRunway: boolean; crashed: boolean; crashReason: string | null
  stalled: boolean; stallMargin: number; afterburner: boolean; position: Vec3; health: number
  stickPitch: number; stickRoll: number; rudder: number; elevator: number; aileron: number; rudderSurface: number
}

export function emptyTelemetry(): Telemetry {
  return {
    time: 0, airspeedKt: 0, groundSpeedKt: 0, altitudeFt: 0, aglFt: 0, verticalSpeedFpm: 0, pitchDeg: 0,
    bankDeg: 0, headingDeg: 0, trackDeg: 0, alphaDeg: 0, slipDeg: 0, turnRateDegPerSec: 0, gLoad: 1,
    throttle: 0, engine: 0, flapsDeg: 0, gearDown: true, trim: 0, brakes: 0, onGround: false, onRunway: false,
    crashed: false, crashReason: null, stalled: false, stallMargin: 1, afterburner: false, position: new Vec3(),
    health: 100, stickPitch: 0, stickRoll: 0, rudder: 0, elevator: 0, aileron: 0, rudderSurface: 0,
  }
}

export function makeTelemetry(a: Aircraft, input: PilotInput, time: number): Telemetry {
  const s = a.state
  const horiz = new Vec3(s.velocity.x, 0, s.velocity.z)
  const omegaWorld = s.orientation.act(s.angularVelocity)
  const detents = a.spec.flapDetents
  return {
    time,
    airspeedKt: a.aero.airspeed / Units.knot,
    groundSpeedKt: horiz.length() / Units.knot,
    altitudeFt: s.position.y / Units.foot,
    aglFt: (s.position.y - Terrain.height(s.position.x, s.position.z)) / Units.foot,
    verticalSpeedFpm: s.velocity.y / Units.feetPerMinute,
    pitchDeg: s.pitchDeg,
    bankDeg: s.bankDeg,
    headingDeg: s.headingDeg,
    trackDeg: horiz.length() > 1 ? wrap360(deg(Math.atan2(horiz.x, -horiz.z))) : s.headingDeg,
    alphaDeg: deg(a.aero.alpha),
    slipDeg: deg(a.aero.beta),
    turnRateDegPerSec: -deg(omegaWorld.y),
    gLoad: s.loadFactor,
    throttle: input.throttle,
    engine: s.engine,
    flapsDeg: s.flaps * (detents[detents.length - 1] ?? 0),
    gearDown: s.gearDown,
    trim: s.elevatorTrim,
    brakes: input.brakes,
    onGround: s.onGround,
    onRunway: s.onGround && Terrain.isOnRunway(s.position.x, s.position.z),
    crashed: s.crashed,
    crashReason: s.crashReason,
    stalled: a.aero.stalled && !s.onGround,
    stallMargin: a.aero.stallMargin,
    afterburner: a.spec.isJet && s.engine > 0.95,
    position: s.position.clone(),
    health: s.health,
    stickPitch: input.pitch,
    stickRoll: input.roll,
    rudder: input.yaw,
    elevator: s.surfaces.elevator,
    aileron: s.surfaces.aileron,
    rudderSurface: s.surfaces.rudder,
  }
}
