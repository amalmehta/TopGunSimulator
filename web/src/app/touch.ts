// On-screen flight controls for phones and tablets: a virtual stick (left), throttle and rudder
// (right) and action buttons. Every control tracks its own pointer, so you can fly and
// change power at the same time.
import type { FlightAction } from './input'

/** Maps a drag offset (px) inside a stick of the given radius to axes in -1...1 with a small dead zone. */
export function stickAxes(dx: number, dy: number, radius: number, deadZone = 0.08) {
  let x = dx / radius, y = dy / radius
  const len = Math.hypot(x, y)
  if (len > 1) { x /= len; y /= len }
  const shape = (v: number) => (Math.abs(v) < deadZone ? 0 : Math.sign(v) * (Math.abs(v) - deadZone) / (1 - deadZone))
  // Drag down = pull back = nose up (+pitch), like a real stick or a gamepad.
  return { roll: shape(x), pitch: shape(y) }
}

/** Pointer capture keeps a drag on its control even if the finger slides off; it can throw for stale pointers. */
function capture(el: HTMLElement, id: number) { try { capture(el, id) } catch { /* drag still works without capture */ } }

export interface TouchState { active: boolean; stickHeld: boolean; pitch: number; roll: number; yaw: number; throttle: number | null; brakes: boolean; trigger: boolean }

export class TouchControls {
  state: TouchState = { active: false, stickHeld: false, pitch: 0, roll: 0, yaw: 0, throttle: null, brakes: false, trigger: false }
  onAction: ((a: FlightAction) => void) | null = null
  /** Tapped the Level button (re-centre tilt, or ask for motion permission first). */
  onLevel: (() => void) | null = null
  readonly root: HTMLDivElement
  private knob: HTMLDivElement
  private throttleFill: HTMLDivElement
  private throttleLabel: HTMLSpanElement
  private gunBtn: HTMLButtonElement
  private gearBtn: HTMLButtonElement
  private levelBtn: HTMLButtonElement

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div')
    this.root.id = 'touch-controls'
    this.root.hidden = true
    this.root.innerHTML = `
      <div class="tc-stick" aria-label="Flight stick"><div class="tc-knob"></div></div>
      <div class="tc-right">
        <div class="tc-buttons">
          <button data-act="flapsUp" aria-label="Flaps up">Flaps ▲</button>
          <button data-act="flapsDown" aria-label="Flaps down">Flaps ▼</button>
          <button data-act="trimUp" aria-label="Trim nose up">Trim ▲</button>
          <button data-act="trimDown" aria-label="Trim nose down">Trim ▼</button>
          <button data-act="toggleGear" class="tc-gear" aria-label="Gear">Gear</button>
          <button data-act="nextCamera" aria-label="Next camera">Cam</button>
          <button data-hold="brakes" aria-label="Brakes (hold)">Brake</button>
          <button data-hold="trigger" class="tc-gun" aria-label="Guns (hold)">Guns</button>
        </div>
        <div class="tc-throttle" aria-label="Throttle"><div class="tc-fill"></div><span>0%</span></div>
      </div>
      <div class="tc-rudder" aria-label="Rudder"><button data-yaw="-1">◀ Rudder</button><button data-yaw="1">Rudder ▶</button><button class="tc-level" hidden aria-label="Level: make this the neutral tilt">Level</button></div>`
    parent.appendChild(this.root)
    this.knob = this.root.querySelector('.tc-knob')!
    this.throttleFill = this.root.querySelector('.tc-fill')!
    this.throttleLabel = this.root.querySelector('.tc-throttle span')!
    this.gunBtn = this.root.querySelector('.tc-gun')!
    this.gearBtn = this.root.querySelector('.tc-gear')!
    this.levelBtn = this.root.querySelector('.tc-level')!
    this.levelBtn.addEventListener('pointerdown', e => { e.preventDefault(); this.onLevel?.() })
    this.bindStick(this.root.querySelector('.tc-stick')!)
    this.bindThrottle(this.root.querySelector('.tc-throttle')!)
    this.bindButtons()
  }

  show(on: boolean, jet: boolean, gear: boolean) {
    this.root.hidden = !on
    this.state.active = on
    this.gunBtn.hidden = !jet
    this.gearBtn.hidden = !gear
    if (!on) this.reset()
  }

  /** Shows the Level button while tilt-to-fly is on; `label` reads "Enable tilt" until motion data arrives. */
  showTilt(on: boolean, label = 'Level') {
    this.levelBtn.hidden = !on
    this.levelBtn.textContent = label
  }

  /** With tilt flying, the knob mirrors the tilt so you can see your input. */
  mirrorTilt(roll: number, pitch: number, radius: number) {
    if (this.state.stickHeld) return
    this.knob.style.transform = roll || pitch ? `translate(${roll * radius}px, ${pitch * radius}px)` : ''
  }

  /** Mirrors the current throttle (from keyboard or a restart) onto the slider. */
  syncThrottle(t: number) {
    this.throttleFill.style.height = `${t * 100}%`
    this.throttleLabel.textContent = `${Math.round(t * 100)}%`
  }

  reset() {
    Object.assign(this.state, { stickHeld: false, pitch: 0, roll: 0, yaw: 0, throttle: null, brakes: false, trigger: false })
    this.knob.style.transform = ''
  }

  private bindStick(el: HTMLDivElement) {
    let id: number | null = null
    const move = (e: PointerEvent) => {
      const r = el.getBoundingClientRect()
      const radius = r.width / 2
      let dx = e.clientX - (r.left + radius), dy = e.clientY - (r.top + radius)
      const len = Math.hypot(dx, dy)
      if (len > radius) { dx *= radius / len; dy *= radius / len }
      this.knob.style.transform = `translate(${dx}px, ${dy}px)`
      const a = stickAxes(dx, dy, radius)
      this.state.pitch = a.pitch
      this.state.roll = a.roll
    }
    el.addEventListener('pointerdown', e => { id = e.pointerId; capture(el, id); this.state.stickHeld = true; move(e); e.preventDefault() })
    el.addEventListener('pointermove', e => { if (e.pointerId === id) move(e) })
    const release = (e: PointerEvent) => {
      if (e.pointerId !== id) return
      id = null
      this.state.stickHeld = false
      this.state.pitch = 0; this.state.roll = 0
      this.knob.style.transform = ''
    }
    el.addEventListener('pointerup', release)
    el.addEventListener('pointercancel', release)
  }

  private bindThrottle(el: HTMLDivElement) {
    let id: number | null = null
    const set = (e: PointerEvent) => {
      const r = el.getBoundingClientRect()
      const t = Math.min(1, Math.max(0, 1 - (e.clientY - r.top) / r.height))
      this.state.throttle = t
      this.syncThrottle(t)
    }
    el.addEventListener('pointerdown', e => { id = e.pointerId; capture(el, id); set(e); e.preventDefault() })
    el.addEventListener('pointermove', e => { if (e.pointerId === id) set(e) })
    el.addEventListener('pointerup', e => { if (e.pointerId === id) id = null })
    el.addEventListener('pointercancel', e => { if (e.pointerId === id) id = null })
  }

  private bindButtons() {
    const hold = (el: HTMLElement, on: () => void, off: () => void) => {
      el.addEventListener('pointerdown', e => { capture(el, e.pointerId); el.classList.add('down'); on(); e.preventDefault() })
      for (const ev of ['pointerup', 'pointercancel'] as const) el.addEventListener(ev, () => { el.classList.remove('down'); off() })
    }
    this.root.querySelectorAll<HTMLButtonElement>('[data-act]').forEach(b => {
      b.addEventListener('pointerdown', e => { e.preventDefault(); this.onAction?.(b.dataset.act as FlightAction) })
    })
    this.root.querySelectorAll<HTMLButtonElement>('[data-hold]').forEach(b => {
      const key = b.dataset.hold as 'brakes' | 'trigger'
      hold(b, () => { this.state[key] = true }, () => { this.state[key] = false })
    })
    this.root.querySelectorAll<HTMLButtonElement>('[data-yaw]').forEach(b => {
      const v = Number(b.dataset.yaw)
      hold(b, () => { this.state.yaw = v }, () => { if (this.state.yaw === v) this.state.yaw = 0 })
    })
  }
}

/** Rewrites keyboard hints in lesson and instructor text into touch-control terms. */
const TOUCH_TEXT: [RegExp, string][] = [
  [/\((S or ↓|S \/ ↓)\)/g, '(drag the stick down)'],
  [/\(W or ↑\)/g, '(push the stick up)'],
  [/\(A or ←\)/g, '(stick left)'],
  [/\(D or →\)/g, '(stick right)'],
  [/\((Q or E|E \/ Q)\)/g, '(Rudder buttons)'],
  [/\(E\)/g, '(Rudder ▶)'],
  [/\(Q\)/g, '(◀ Rudder)'],
  [/\(hold R\)|\(R\)/g, '(slide the throttle up)'],
  [/\(F\)/g, '(slide the throttle down)'],
  [/\(B\)/g, '(Brake button)'],
  [/\(Space\)/g, '(Guns button)'],
  [/hold Space/g, 'hold Guns'],
  [/Press G/g, 'Tap Gear'],
  [/\] twice more/g, 'Flaps ▼ twice more'],
  [/\(, nose down \/ \. nose up\)/g, '(Trim ▲ / Trim ▼)'],
  [/with , and \./g, 'with the Trim buttons'],
  [/keep it straight with Q\/E/g, 'keep it straight with the Rudder buttons'],
]
export const touchText = (s: string) => TOUCH_TEXT.reduce((acc, [re, to]) => acc.replace(re, to), s)

const TILT_TEXT: [RegExp, string][] = [
  [/\(drag the stick down\)/g, '(tilt the top toward you)'],
  [/\(push the stick up\)/g, '(tilt the top away)'],
  [/\(stick left\)/g, '(tilt left)'],
  [/\(stick right\)/g, '(tilt right)'],
]
/** Like touchText, for flying by tilting the device. */
export const tiltText = (s: string) => TILT_TEXT.reduce((acc, [re, to]) => acc.replace(re, to), touchText(s))
