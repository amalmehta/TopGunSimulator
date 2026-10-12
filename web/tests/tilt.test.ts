import { describe, it, expect } from 'vitest'
import { calibrate, tiltAxes, TILT_RANGE_DEG, type Gravity } from '../src/app/tilt'
import { InputManager } from '../src/app/input'
import { DEFAULTS } from '../src/app/settings'
import { tiltText } from '../src/app/touch'

;(globalThis as { window?: unknown }).window ??= { addEventListener() {} }

const G = 9.81, rad = (d: number) => (d * Math.PI) / 180
/** Gravity reading (Android convention: +z when face-up) for a device pitched toward you by `pitch` and rolled right by `roll`. */
function reading(pitchDeg: number, rollDeg: number, sign = 1): Gravity {
  const p = rad(pitchDeg), r = rad(rollDeg)
  return { x: -Math.sin(r) * G * sign, y: Math.sin(p) * Math.cos(r) * G * sign, z: Math.cos(p) * Math.cos(r) * G * sign }
}

describe('tilt maths', () => {
  const held = reading(35, 0)            // a typical comfortable hold, top tilted toward you
  const n = calibrate(held, 0)

  it('the calibrated hold is neutral', () => {
    expect(tiltAxes(held, 0, n)).toEqual({ roll: 0, pitch: 0 })
  })
  it('tilting the top toward you pulls back; away pushes forward', () => {
    expect(tiltAxes(reading(50, 0), 0, n).pitch).toBeGreaterThan(0.4)
    expect(tiltAxes(reading(20, 0), 0, n).pitch).toBeLessThan(-0.4)
  })
  it('right edge down rolls right, and full stick arrives at the range limit', () => {
    expect(tiltAxes(reading(35, 15), 0, n).roll).toBeGreaterThan(0.4)
    expect(tiltAxes(reading(35, -15), 0, n).roll).toBeLessThan(-0.4)
    expect(tiltAxes(reading(35, TILT_RANGE_DEG + 10), 0, n).roll).toBe(1)
  })
  it('the tilt range setting scales sensitivity', () => {
    const tip = reading(35, 12)
    const sharp = tiltAxes(tip, 0, n, 15).roll, default30 = tiltAxes(tip, 0, n).roll, gentle = tiltAxes(tip, 0, n, 60).roll
    expect(sharp).toBeGreaterThan(default30)
    expect(default30).toBeGreaterThan(gentle)
    expect(tiltAxes(reading(35, 15), 0, n, 15).roll).toBeCloseTo(1, 5)       // full stick right at the chosen range
    expect(tiltAxes(reading(35, 40), 0, n, 60).roll).toBeLessThan(1)
  })
  it('small wobbles inside the dead zone do nothing', () => {
    expect(tiltAxes(reading(36, 1), 0, n)).toEqual({ roll: 0, pitch: 0 })
  })
  it('iOS-style inverted readings give the same answer', () => {
    const ni = calibrate(reading(35, 0, -1), 0)
    expect(tiltAxes(reading(50, 15, -1), 0, ni).pitch).toBeCloseTo(tiltAxes(reading(50, 15), 0, n).pitch, 6)
    expect(tiltAxes(reading(50, 15, -1), 0, ni).roll).toBeCloseTo(tiltAxes(reading(50, 15), 0, n).roll, 6)
  })
  it('works in landscape: the screen rotation is undone before measuring', () => {
    // Screen rotated 90°: screen-right is device -y and screen-up is device +x.
    const toDevice = (g: Gravity): Gravity => ({ x: g.y, y: -g.x, z: g.z })
    const nl = calibrate(toDevice(reading(35, 0)), 90)
    const a = tiltAxes(toDevice(reading(50, 15)), 90, nl)
    expect(a.pitch).toBeGreaterThan(0.4)
    expect(a.roll).toBeGreaterThan(0.4)
  })
})

describe('tilt input', () => {
  const touchIdle = { active: true, stickHeld: false, pitch: 0, roll: 0, yaw: 0, throttle: null, brakes: false, trigger: false }
  it('tilt flies when the stick is not held', () => {
    const i = new InputManager().sample(1 / 60, DEFAULTS, touchIdle, { enabled: true, receiving: true, pitch: 0.6, roll: -0.3 })
    expect(i.pitch).toBeCloseTo(0.6); expect(i.roll).toBeCloseTo(-0.3)
  })
  it('a finger on the on-screen stick overrides tilt', () => {
    const touch = { ...touchIdle, stickHeld: true, pitch: -0.2, roll: 0.1 }
    const i = new InputManager().sample(1 / 60, DEFAULTS, touch, { enabled: true, receiving: true, pitch: 0.9, roll: 0.9 })
    expect(i.pitch).toBeCloseTo(-0.2); expect(i.roll).toBeCloseTo(0.1)
  })
  it('no motion data means no tilt input', () => {
    const i = new InputManager().sample(1 / 60, DEFAULTS, touchIdle, { enabled: true, receiving: false, pitch: 0.9, roll: 0.9 })
    expect(i.pitch).toBe(0); expect(i.roll).toBe(0)
  })
  it('lesson wording talks about tilting', () => {
    expect(tiltText('Pull back gently (S or ↓) until the nose is 10° up.')).toBe('Pull back gently (tilt the top toward you) until the nose is 10° up.')
    expect(tiltText('Push the stick left (A or ←) to bank 30° left.')).toBe('Push the stick left (tilt left) to bank 30° left.')
  })
})
