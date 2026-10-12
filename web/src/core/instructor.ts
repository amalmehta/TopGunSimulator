// Port of FlightCore/Instructor.swift.
import type { AircraftSpec } from './aircraft'
import type { Telemetry } from './telemetry'

export type Severity = 0 | 1 | 2   // info, caution, warning
export const Severity = { info: 0 as Severity, caution: 1 as Severity, warning: 2 as Severity }
export interface Hint { id: string; severity: Severity; text: string; why: string }

const i = Math.trunc

export class Instructor {
  private pitchHoldTime = 0
  private lastPitchInput = 0

  evaluate(t: Telemetry, spec: AircraftSpec, dt: number): Hint[] {
    const hints: Hint[] = []
    if (t.crashed) return hints
    const airborne = !t.onGround

    if (Math.abs(t.stickPitch) > 0.08 && Math.abs(t.stickPitch - this.lastPitchInput) < 0.05) this.pitchHoldTime += dt
    else this.pitchHoldTime = 0
    this.lastPitchInput = t.stickPitch

    if (t.stalled) {
      hints.push({ id: 'stall', severity: Severity.warning, text: 'STALL: push forward, wings level, full power',
        why: `The wing is past its critical angle of attack (${i(t.alphaDeg)}°) and has lost lift. Only lowering the angle of attack (stick forward) fixes a stall. Pulling back makes it worse.` })
    } else if (airborne && t.stallMargin < 0.2 && t.airspeedKt > 5) {
      hints.push({ id: 'stallWarning', severity: Severity.caution, text: 'Stall warning: ease the back pressure',
        why: `Angle of attack is ${i(t.alphaDeg)}°, close to the stall. A wing can stall at any airspeed; it's the angle that matters.` })
    }

    if (airborne && t.aglFt < 400 && t.verticalSpeedFpm < -1500) {
      hints.push({ id: 'sinkRate', severity: Severity.warning, text: 'SINK RATE: pull up!',
        why: `You're descending at ${i(-t.verticalSpeedFpm)} fpm only ${i(t.aglFt)} ft above the ground.` })
    } else if (airborne && t.aglFt < 200 && !t.gearDown && t.airspeedKt < spec.vApproachKt * 1.3) {
      hints.push({ id: 'gear', severity: Severity.warning, text: 'Gear is up! Press G',
        why: "You're low and slow like you're landing, but the wheels are still retracted." })
    }

    if (t.airspeedKt > spec.vNeKt) {
      hints.push({ id: 'overspeed', severity: Severity.warning, text: 'Overspeed: reduce power, raise the nose',
        why: `Above the never-exceed speed (${i(spec.vNeKt)} kt) the airframe can be damaged.` })
    }

    if (t.gLoad > spec.gLimit + 0.3) {
      hints.push({ id: 'overG', severity: Severity.warning, text: `Over-G (${t.gLoad.toFixed(1)} g): ease off`,
        why: `The structure is rated to ${spec.gLimit} g. Pulling harder doesn't turn you much faster; it bleeds energy.` })
    }

    if (airborne && Math.abs(t.slipDeg) > 4 && t.airspeedKt > spec.vStallKt * 0.8 && !t.stalled) {
      const side = t.slipDeg > 0 ? 'right' : 'left'
      hints.push({ id: 'slip', severity: Severity.info, text: `Uncoordinated: step on the ${side} rudder (${side === 'right' ? 'E' : 'Q'})`,
        why: `The aircraft is slipping sideways through the air (${Math.abs(t.slipDeg).toFixed(0)}°). That adds drag, and near a stall a slip can drop a wing into a spin. Keep the ball centred.` })
    }

    if (airborne && Math.abs(t.bankDeg) > (spec.kind === 'trainer' ? 50 : 80) && !t.stalled) {
      hints.push({ id: 'steepBank', severity: Severity.caution, text: `Steep bank (${i(Math.abs(t.bankDeg))}°): roll out or add back pressure and power`,
        why: 'In a bank only part of the lift points up. At 60° you need twice the lift (2 g) just to hold altitude.' })
    }

    if (airborne && t.verticalSpeedFpm > 300 && t.engine < 0.3 && t.airspeedKt < spec.vClimbKt * 0.9 && !t.stalled) {
      hints.push({ id: 'climbNoPower', severity: Severity.caution, text: "Climbing on low power: you're trading speed for height",
        why: 'Pitch controls airspeed and power controls climb. Without power a climb just bleeds airspeed until you stall.' })
    }

    if (airborne && this.pitchHoldTime > 5) {
      hints.push({ id: 'trim', severity: Severity.info, text: 'Holding pressure? Trim it out with , and .',
        why: 'Trim moves a small tab so the aircraft holds this attitude by itself. Pilots trim constantly so they can fly with a light touch.' })
    }

    if (t.onGround && t.airspeedKt < 1 && t.throttle < 0.05 && !t.crashed) {
      hints.push({ id: 'ready', severity: Severity.info, text: `Ready for takeoff: full power (R), keep it straight with Q/E, rotate at ${i(spec.vRotateKt)} kt`,
        why: "Raise the nose gently at rotation speed and the wing will lift you off. Don't yank it off early." })
    } else if (t.onGround && t.airspeedKt > spec.vRotateKt && t.pitchDeg < 3 && t.throttle > 0.7) {
      hints.push({ id: 'rotate', severity: Severity.info, text: 'Rotate: ease back on the stick (S / ↓)',
        why: `You're past rotation speed (${i(spec.vRotateKt)} kt). Raise the nose about 8–10° and let it fly off.` })
    }

    return hints.sort((a, b) => b.severity - a.severity)
  }
}
