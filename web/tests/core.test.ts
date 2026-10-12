// Ports of the key FlightCore XCTests.
import { describe, it, expect } from 'vitest'
import { Vec3, Units, clamp, rad, quatFromEuler } from '../src/core/math'
import { Atmosphere, Terrain } from '../src/core/environment'
import { Aircraft, AircraftState, PilotInput, TRAINER, FIGHTER } from '../src/core/aircraft'
import { FlightSession, onTarget } from '../src/core/session'
import { Instructor } from '../src/core/instructor'
import { lessonById, LESSONS } from '../src/core/lessons'
import { emptyTelemetry } from '../src/core/telemetry'

const dt = 1 / FlightSession.physicsRate
const fly = (a: Aircraft, seconds: number, input: PilotInput) => { for (let i = 0; i < seconds / dt; i++) a.step(dt, input, new Vec3()) }
const inp = (o: Partial<PilotInput>) => Object.assign(new PilotInput(), o)
const lessonSession = (id: string) => new FlightSession({ kind: 'lesson', lesson: lessonById(id)! })

describe('environment', () => {
  it('standard atmosphere', () => {
    expect(Atmosphere.density(0)).toBeCloseTo(1.225, 6)
    expect(Math.abs(Atmosphere.density(3048) - 0.905)).toBeLessThan(0.01)
  })
  it('airport flat, canyon below walls, approach flat', () => {
    expect(Terrain.height(0, 0)).toBe(0)
    const z = -11000, c = Terrain.canyonCenterX(z)
    expect(Terrain.height(c, z) + 300).toBeLessThan(Terrain.height(c + 900, z))
    for (let zz = Terrain.runwaySouthEnd; zz <= Terrain.runwaySouthEnd + 6000; zz += 250) expect(Terrain.height(0, zz)).toBe(0)
  })
  it('euler round trip', () => {
    const s = new AircraftState()
    s.orientation = quatFromEuler(135, 10, 20)
    expect(s.headingDeg).toBeCloseTo(135, 2); expect(s.pitchDeg).toBeCloseTo(10, 2); expect(s.bankDeg).toBeCloseTo(20, 2)
  })
})

describe('flight model', () => {
  it('trimmed trainer holds altitude hands-off', () => {
    const a = new Aircraft(TRAINER)
    a.placeInFlight(new Vec3(0, 1000, 0), 0, 100)
    fly(a, 30, inp({ throttle: a.state.engine }))
    expect(Math.abs(a.state.position.y - 1000)).toBeLessThan(60)
    expect(Math.abs(a.state.bankDeg)).toBeLessThan(5)
  })
  it('stalls at full aft stick and recovers', () => {
    const a = new Aircraft(TRAINER)
    a.placeInFlight(new Vec3(0, 1500, 0), 0, 80)
    let stalled = false
    for (let i = 0; i < 15 / dt && !stalled; i++) { a.step(dt, inp({ pitch: 1 }), new Vec3()); stalled = a.aero.stalled }
    expect(stalled).toBe(true)
    fly(a, 4, inp({ pitch: -0.3, throttle: 1 }))
    expect(a.aero.stalled).toBe(false)
    expect(a.state.crashed).toBe(false)
  })
  it('fighter g-limiter holds under 9 g', () => {
    const a = new Aircraft(FIGHTER)
    a.placeInFlight(new Vec3(0, 4000, 0), 0, 450, false)
    let maxG = 0
    for (let i = 0; i < 4 / dt; i++) { a.step(dt, inp({ throttle: 1, pitch: 1 }), new Vec3()); maxG = Math.max(maxG, a.state.loadFactor) }
    expect(maxG).toBeGreaterThan(6); expect(maxG).toBeLessThan(9)
  })
  it('sits still on the runway', () => {
    for (const spec of [TRAINER, FIGHTER]) {
      const a = new Aircraft(spec)
      a.placeOnRunway()
      fly(a, 5, inp({ brakes: 1 }))
      expect(a.state.crashed).toBe(false)
      expect(a.state.wheelsOnGround).toBe(3)
    }
  })
  it('hard landing crashes', () => {
    const a = new Aircraft(TRAINER)
    a.placeInFlight(new Vec3(0, 5, 0), 0, 60, null, 1)
    a.state.velocity.y = -8
    fly(a, 2, inp({}))
    expect(a.state.crashed).toBe(true)
  })
})

describe('session and lessons', () => {
  it('steps wait for their condition', () => {
    for (const id of ['dogfight', 'canyon-run', 'landing', 'takeoff']) {
      const s = lessonSession(id)
      for (let i = 0; i < 60; i++) s.advance(1 / 60)
      expect(s.lesson!.stepIndex, id).toBe(0)
    }
  })
  it('every lesson starts cleanly', () => {
    for (const l of LESSONS) {
      const s = new FlightSession({ kind: 'lesson', lesson: l })
      for (let i = 0; i < 120; i++) s.advance(1 / 60)
      expect(s.player.state.crashed, l.title).toBe(false)
      expect(s.outcome?.kind, l.title).toBe('running')
    }
  })
  it('scripted pilot passes the takeoff lesson', () => {
    const s = lessonSession('takeoff')
    s.input.throttle = 1
    for (let i = 0; i < 60 * 90 && s.outcome?.kind === 'running'; i++) {
      const t = s.telemetry
      s.input.pitch = t.airspeedKt > 55 ? clamp((9 - t.pitchDeg) * 0.06, -0.4, 0.5) : 0
      s.advance(1 / 60)
    }
    expect(s.outcome?.kind).toBe('passed')
  })
  it('gates pass and miss', () => {
    const s = lessonSession('canyon-run')
    const g = s.gates[0]
    s.updateGates(g.center.sub(g.normal.mul(5)), g.center.add(g.normal.mul(5)))
    expect(s.gates[0].status).toBe('passed')
    const g2 = s.gates[1], up = new Vec3(0, 200, 0)
    s.updateGates(g2.center.sub(g2.normal.mul(5)).add(up), g2.center.add(g2.normal.mul(5)).add(up))
    expect(s.gates[1].status).toBe('missed')
  })
  it('guns on target', () => {
    const shooter = { position: new Vec3(), forward: new Vec3(0, 0, -1) }
    expect(onTarget(shooter, { position: new Vec3(0, 0, -500) }, rad(1), 1000)).toBe(true)
    expect(onTarget(shooter, { position: new Vec3(100, 0, -500) }, rad(1), 1000)).toBe(false)
  })
  it('bandit closes for the merge', () => {
    const s = lessonSession('dogfight')
    s.input.throttle = 0.9
    let min = s.banditDistance!
    for (let i = 0; i < 60 * 40; i++) { s.advance(1 / 60); min = Math.min(min, s.banditDistance!) }
    expect(min).toBeLessThan(1500)
    expect(s.bandit!.state.crashed).toBe(false)
  })
  it('instructor flags a stall first', () => {
    const t = { ...emptyTelemetry(), stalled: true, alphaDeg: 18 }
    expect(new Instructor().evaluate(t, TRAINER, 0.1)[0]?.id).toBe('stall')
  })
  it('units sanity', () => { expect(Units.knot).toBeCloseTo(0.514444, 6) })
})
