// Replays the Swift reference trajectories (exported by GoldenExportTests.swift) through the
// TypeScript port and checks they match. Keep the input scripts identical to the Swift ones.
import { describe, it, expect } from 'vitest'
import golden from './fixtures/golden.json'
import { Vec3, Units, clamp } from '../src/core/math'
import { Aircraft, PilotInput, TRAINER, FIGHTER } from '../src/core/aircraft'
import { FlightSession } from '../src/core/session'

type Script = (t: number, a: Aircraft) => PilotInput
function scenarios(): [string, Aircraft, number, Script][] {
  const maneuvers = new Aircraft(TRAINER)
  maneuvers.placeInFlight(new Vec3(0, 1000, 0), 0, 100)
  const cruiseThrottle = maneuvers.state.engine
  const takeoff = new Aircraft(TRAINER)
  takeoff.placeOnRunway()
  const pull = new Aircraft(FIGHTER)
  pull.placeInFlight(new Vec3(0, 4000, 0), 0, 450, false)
  const stall = new Aircraft(TRAINER)
  stall.placeInFlight(new Vec3(0, 1500, 0), 0, 80)
  const inp = (o: Partial<PilotInput>) => Object.assign(new PilotInput(), o)
  return [
    ['trainer-maneuvers', maneuvers, 12, t => inp({
      throttle: cruiseThrottle, pitch: t < 1 ? 0.3 : 0,
      roll: t >= 2 && t < 3 ? 0.5 : t >= 5 && t < 6 ? -0.5 : 0, yaw: t >= 7 && t < 8 ? 0.6 : 0 })],
    ['trainer-takeoff', takeoff, 30, (_, a) => inp({
      throttle: 1, pitch: a.aero.airspeed / Units.knot > 55 ? clamp((9 - a.state.pitchDeg) * 0.06, -0.4, 0.5) : 0 })],
    ['fighter-pull', pull, 6, t => inp({ throttle: 1, pitch: t < 3 ? 1 : 0, roll: t >= 3 && t < 4 ? 1 : 0 })],
    ['trainer-stall', stall, 10, () => inp({ throttle: 0, pitch: 1 })],
  ]
}

describe('TypeScript flight model matches the Swift FlightCore', () => {
  for (const [name, a, seconds, script] of scenarios()) {
    it(name, () => {
      const ref = (golden as Record<string, number[][]>)[name]
      const dt = 1 / FlightSession.physicsRate
      const n = Math.round(seconds / dt)
      const got: number[][] = []
      for (let i = 0; i < n; i++) {
        a.step(dt, script(i * dt, a), new Vec3())
        if ((i + 1) % 120 === 0) {
          const s = a.state, o = s.orientation
          got.push([(i + 1) * dt, s.position.x, s.position.y, s.position.z, s.velocity.x, s.velocity.y, s.velocity.z,
            o.x, o.y, o.z, o.w, a.aero.alpha, s.crashed ? 1 : 0])
        }
      }
      expect(got.length).toBe(ref.length)
      let worstPos = 0
      for (let k = 0; k < ref.length; k++) {
        const r = ref[k], g = got[k]
        worstPos = Math.max(worstPos, Math.hypot(r[1] - g[1], r[2] - g[2], r[3] - g[3]))
        for (let j = 4; j < 7; j++) expect(Math.abs(r[j] - g[j]), `${name} velocity[${j}] at t=${r[0]}`).toBeLessThan(1e-3)
        for (let j = 7; j < 11; j++) expect(Math.abs(r[j] - g[j]), `${name} quat[${j}] at t=${r[0]}`).toBeLessThan(1e-5)
        expect(g[12]).toBe(r[12])
      }
      expect(worstPos, `${name} worst position error (m)`).toBeLessThan(1e-2)
    })
  }
})
