// Tilt-to-fly: turns the device's gravity reading into stick input.
// Uses accelerationIncludingGravity (no gimbal flip near vertical, unlike beta/gamma) and the
// screen rotation, measured relative to a neutral attitude captured by calibration.

export interface Gravity { x: number; y: number; z: number }
export interface TiltNeutral { roll: number; pitch: number; sign: number }

const DEG = Math.PI / 180
/** Full stick at this much tilt from neutral. */
export const TILT_RANGE_DEG = 30
const DEAD_DEG = 2

/** Gravity in screen axes (x = screen right, y = screen up), for a screen rotated `angle` degrees. */
export function toScreen(g: Gravity, angle: number) {
  const a = angle * DEG, c = Math.cos(a), s = Math.sin(a)
  return { x: g.x * c - g.y * s, y: g.x * s + g.y * c, z: g.z }
}

/** Raw roll/pitch angles (radians). `sign` normalises iOS vs Android accelerometer sign conventions. */
export function rawAngles(g: Gravity, angle: number, sign: number) {
  const s = toScreen({ x: g.x * sign, y: g.y * sign, z: g.z * sign }, angle)
  const len = Math.hypot(s.x, s.y, s.z) || 1
  return {
    roll: Math.asin(Math.max(-1, Math.min(1, -s.x / len))),   // right edge down → roll right
    pitch: Math.atan2(s.y, s.z),                               // top edge toward you → nose up
  }
}

/** Captures the current hold as neutral. The screen faces up-ish while you look at it, so z should be positive. */
export function calibrate(g: Gravity, angle: number): TiltNeutral {
  const sign = g.z < 0 ? -1 : 1
  const a = rawAngles(g, angle, sign)
  return { roll: a.roll, pitch: a.pitch, sign }
}

/** Stick axes in -1...1 from tilt relative to neutral, with a small dead zone. */
export function tiltAxes(g: Gravity, angle: number, n: TiltNeutral) {
  const a = rawAngles(g, angle, n.sign)
  let dPitch = a.pitch - n.pitch
  if (dPitch > Math.PI) dPitch -= 2 * Math.PI
  if (dPitch < -Math.PI) dPitch += 2 * Math.PI
  const shape = (rad: number) => {
    const d = rad / DEG
    if (Math.abs(d) < DEAD_DEG) return 0
    return Math.max(-1, Math.min(1, (Math.sign(d) * (Math.abs(d) - DEAD_DEG)) / (TILT_RANGE_DEG - DEAD_DEG)))
  }
  return { roll: shape(a.roll - n.roll), pitch: shape(dPitch) }
}

type PermissionAPI = { requestPermission?: () => Promise<'granted' | 'denied'> }

/** Listens to device motion and exposes the current tilt stick. */
export class TiltControl {
  enabled = false
  roll = 0
  pitch = 0
  /** True once motion events with gravity have actually arrived. */
  receiving = false
  private neutral: TiltNeutral | null = null
  private last: Gravity | null = null
  private listening = false

  static get supported() { return typeof window !== 'undefined' && 'DeviceMotionEvent' in window }

  /** Must be called from a user gesture on iOS. Resolves false if permission is denied or unsupported. */
  static async requestPermission(): Promise<boolean> {
    if (!TiltControl.supported) return false
    const api = (window as unknown as { DeviceMotionEvent: PermissionAPI }).DeviceMotionEvent
    if (typeof api.requestPermission !== 'function') return true
    try { return (await api.requestPermission()) === 'granted' } catch { return false }
  }

  private angle() {
    const o = screen.orientation?.angle
    if (typeof o === 'number') return o
    const w = (window as unknown as { orientation?: number }).orientation
    return typeof w === 'number' ? w : 0
  }

  private onMotion = (e: DeviceMotionEvent) => {
    const g = e.accelerationIncludingGravity
    if (!g || g.x === null || g.y === null || g.z === null) return
    this.last = { x: g.x, y: g.y, z: g.z }
    this.receiving = true
    if (!this.neutral) this.neutral = calibrate(this.last, this.angle())
    const a = tiltAxes(this.last, this.angle(), this.neutral)
    this.roll = a.roll
    this.pitch = a.pitch
  }

  setEnabled(on: boolean) {
    this.enabled = on
    if (on && !this.listening && TiltControl.supported) { window.addEventListener('devicemotion', this.onMotion); this.listening = true }
    if (!on && this.listening) { window.removeEventListener('devicemotion', this.onMotion); this.listening = false }
    if (!on) { this.roll = 0; this.pitch = 0; this.receiving = false }
  }

  /** Makes the current hold the neutral (level-flight) attitude. */
  recenter() {
    this.neutral = this.last ? calibrate(this.last, this.angle()) : null
    this.roll = 0
    this.pitch = 0
  }
}
