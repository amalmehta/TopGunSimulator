import { describe, it, expect } from 'vitest'
import { stickAxes, touchText } from '../src/app/touch'
import { LESSONS } from '../src/core/lessons'
import { InputManager } from '../src/app/input'
import { DEFAULTS } from '../src/app/settings'

// InputManager registers key listeners on window; tests run in Node, so give it a stub.
;(globalThis as { window?: unknown }).window ??= { addEventListener() {} }

describe('touch stick', () => {
  it('centre is neutral and the dead zone swallows tiny drags', () => {
    expect(stickAxes(0, 0, 60)).toEqual({ roll: 0, pitch: 0 })
    expect(stickAxes(3, -3, 60)).toEqual({ roll: 0, pitch: 0 })
  })
  it('drag down pulls back (nose up), drag right rolls right, full deflection at the rim', () => {
    expect(stickAxes(0, 60, 60).pitch).toBeCloseTo(1)
    expect(stickAxes(0, -60, 60).pitch).toBeCloseTo(-1)
    expect(stickAxes(60, 0, 60).roll).toBeCloseTo(1)
    const diag = stickAxes(200, 200, 60)
    expect(Math.hypot(diag.roll, diag.pitch)).toBeLessThanOrEqual(Math.SQRT2)
    expect(diag.roll).toBeCloseTo(diag.pitch)
  })
})

describe('input merges touch', () => {
  it('touch stick, rudder, throttle, brakes and guns reach the pilot input', () => {
    const im = new InputManager()
    const touch = { active: true, pitch: 0.5, roll: -0.25, yaw: 1, throttle: 0.8, brakes: true, trigger: true }
    const i = im.sample(1 / 60, DEFAULTS, touch)
    expect(i.pitch).toBeCloseTo(0.5)
    expect(i.roll).toBeCloseTo(-0.25)
    expect(i.yaw).toBe(1)
    expect(i.throttle).toBeCloseTo(0.8)
    expect(i.brakes).toBe(1)
    expect(i.trigger).toBe(true)
    expect(touch.throttle).toBeNull()          // consumed; throttle stays where the slider left it
    expect(im.sample(1 / 60, DEFAULTS, { ...touch, throttle: null }).throttle).toBeCloseTo(0.8)
  })
  it('inactive touch state is ignored', () => {
    const i = new InputManager().sample(1 / 60, DEFAULTS, { active: false, pitch: 1, roll: 1, yaw: 1, throttle: 1, brakes: true, trigger: true })
    expect(i.pitch).toBe(0); expect(i.throttle).toBe(0); expect(i.trigger).toBe(false)
  })
})

describe('touch wording', () => {
  it('rewrites key hints into touch terms', () => {
    expect(touchText('Pull back gently (S or ↓) until the nose is 10° up.')).toBe('Pull back gently (drag the stick down) until the nose is 10° up.')
    expect(touchText('Gear is up! Press G')).toBe('Gear is up! Tap Gear')
    expect(touchText('step on the right rudder (E)')).toBe('step on the right rudder (Rudder ▶)')
  })
  it('leaves no single-key hints in any lesson instruction', () => {
    for (const l of LESSONS) for (const s of l.steps) {
      expect(touchText(s.instruction), `${l.title} / ${s.title}`).not.toMatch(/\((?:[A-Z]|hold [A-Z]|[A-Z] (?:or|\/) .)\)|Space\b|\] twice/)
    }
  })
})
