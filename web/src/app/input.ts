// Keyboard and Gamepad API → smooth stick, rudder and throttle (port of InputManager.swift).
import { PilotInput } from '../core/aircraft'
import { clamp } from '../core/math'
import type { Settings } from './settings'

export type FlightAction = 'flapsUp' | 'flapsDown' | 'toggleGear' | 'trimUp' | 'trimDown' | 'nextCamera'
  | 'togglePause' | 'toggleHelp' | 'toggleSidebar' | 'toggleInstruments' | 'endFlight' | 'restart'

const ACTIONS: Record<string, FlightAction> = {
  BracketRight: 'flapsDown', BracketLeft: 'flapsUp', KeyG: 'toggleGear', Period: 'trimUp', Comma: 'trimDown',
  KeyC: 'nextCamera', KeyP: 'togglePause', KeyH: 'toggleHelp', KeyM: 'toggleSidebar', KeyI: 'toggleInstruments',
  Escape: 'endFlight', Backslash: 'restart',
}
const AXIS_KEYS = new Set(['KeyW', 'KeyS', 'KeyA', 'KeyD', 'KeyQ', 'KeyE', 'KeyR', 'KeyF', 'KeyB', 'Space',
  'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'])

export class InputManager {
  private pressed = new Set<string>()
  private kbPitch = 0; private kbRoll = 0; private kbYaw = 0
  throttle = 0
  onAction: ((a: FlightAction) => void) | null = null
  private active = false

  constructor() {
    window.addEventListener('keydown', e => {
      if (!this.active || this.isTyping(e) || e.metaKey || e.ctrlKey) return
      const action = ACTIONS[e.code]
      if (action || AXIS_KEYS.has(e.code)) e.preventDefault()
      if (action && !e.repeat) this.onAction?.(action)
      if (AXIS_KEYS.has(e.code)) this.pressed.add(e.code)
    })
    window.addEventListener('keyup', e => this.pressed.delete(e.code))
    window.addEventListener('blur', () => this.pressed.clear())
  }

  private isTyping(e: KeyboardEvent) {
    const t = e.target as HTMLElement | null
    return !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)
  }

  start() { this.active = true }
  stop() { this.active = false; this.pressed.clear() }

  sample(dt: number, s: Settings): PilotInput {
    const held = (...codes: string[]) => codes.some(c => this.pressed.has(c))
    const axis = (cur: number, plus: boolean, minus: boolean, rate: number) => {
      const target = plus === minus ? 0 : plus ? 1 : -1
      const speed = target === 0 ? rate * 2.5 * s.keyboardCentering : rate
      return cur < target ? Math.min(target, cur + speed * dt) : Math.max(target, cur - speed * dt)
    }
    this.kbPitch = axis(this.kbPitch, held('KeyS', 'ArrowDown'), held('KeyW', 'ArrowUp'), 1.6)
    this.kbRoll = axis(this.kbRoll, held('KeyD', 'ArrowRight'), held('KeyA', 'ArrowLeft'), 2.5)
    this.kbYaw = axis(this.kbYaw, held('KeyE'), held('KeyQ'), 2.5)
    if (held('KeyR')) this.throttle = Math.min(1, this.throttle + 0.5 * dt)
    if (held('KeyF')) this.throttle = Math.max(0, this.throttle - 0.5 * dt)

    const input = new PilotInput()
    input.pitch = this.kbPitch * 0.75 * s.stickSensitivity
    input.roll = this.kbRoll * 0.8 * s.stickSensitivity
    input.yaw = this.kbYaw
    input.brakes = held('KeyB') ? 1 : 0
    input.trigger = held('Space')

    const pad = navigator.getGamepads?.().find(p => p && p.connected)
    if (pad) {
      const dead = (v: number) => (Math.abs(v) < 0.08 ? 0 : v)
      const lx = dead(pad.axes[0] ?? 0), ly = dead(pad.axes[1] ?? 0), rx = dead(pad.axes[2] ?? 0)
      if (ly) input.pitch = ly * s.stickSensitivity           // stick pulled back (down) = nose up
      if (lx) input.roll = lx * s.stickSensitivity
      if (rx) input.yaw = rx
      const r2 = pad.buttons[7]?.value ?? 0, l2 = pad.buttons[6]?.value ?? 0
      if (r2 > 0.05) this.throttle = Math.min(1, this.throttle + r2 * 0.6 * dt)
      if (l2 > 0.05) this.throttle = Math.max(0, this.throttle - l2 * 0.6 * dt)
      if (pad.buttons[0]?.pressed) input.trigger = true
      if (pad.buttons[1]?.pressed) input.brakes = 1
    }
    if (s.invertPitch) input.pitch = -input.pitch
    input.pitch = clamp(input.pitch, -1, 1)
    input.roll = clamp(input.roll, -1, 1)
    input.throttle = this.throttle
    return input
  }
}
