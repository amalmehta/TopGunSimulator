// Port of FlightCore/Math.swift. Everything is SI (metres, seconds, kilograms, radians).

export class Vec3 {
  constructor(public x = 0, public y = 0, public z = 0) {}
  static zero() { return new Vec3(0, 0, 0) }
  clone() { return new Vec3(this.x, this.y, this.z) }
  add(v: Vec3) { return new Vec3(this.x + v.x, this.y + v.y, this.z + v.z) }
  sub(v: Vec3) { return new Vec3(this.x - v.x, this.y - v.y, this.z - v.z) }
  mul(s: number) { return new Vec3(this.x * s, this.y * s, this.z * s) }
  /** Component-wise product. */
  hadamard(v: Vec3) { return new Vec3(this.x * v.x, this.y * v.y, this.z * v.z) }
  /** Component-wise division. */
  divv(v: Vec3) { return new Vec3(this.x / v.x, this.y / v.y, this.z / v.z) }
  dot(v: Vec3) { return this.x * v.x + this.y * v.y + this.z * v.z }
  cross(v: Vec3) {
    return new Vec3(this.y * v.z - this.z * v.y, this.z * v.x - this.x * v.z, this.x * v.y - this.y * v.x)
  }
  length() { return Math.sqrt(this.dot(this)) }
  normalized() { const l = this.length(); return l > 0 ? this.mul(1 / l) : new Vec3() }
}

/** Unit quaternion (x, y, z imaginary; w real), Hamilton product like simd_quatd. */
export class Quat {
  constructor(public x = 0, public y = 0, public z = 0, public w = 1) {}
  static identity() { return new Quat(0, 0, 0, 1) }
  static fromAxisAngle(angle: number, axis: Vec3) {
    const a = axis.normalized(), s = Math.sin(angle / 2)
    return new Quat(a.x * s, a.y * s, a.z * s, Math.cos(angle / 2))
  }
  clone() { return new Quat(this.x, this.y, this.z, this.w) }
  mul(q: Quat) {
    return new Quat(
      this.w * q.x + this.x * q.w + this.y * q.z - this.z * q.y,
      this.w * q.y - this.x * q.z + this.y * q.w + this.z * q.x,
      this.w * q.z + this.x * q.y - this.y * q.x + this.z * q.w,
      this.w * q.w - this.x * q.x - this.y * q.y - this.z * q.z,
    )
  }
  conjugate() { return new Quat(-this.x, -this.y, -this.z, this.w) }
  /** Inverse of a unit quaternion. */
  inverse() { return this.conjugate() }
  normalized() {
    const l = Math.hypot(this.x, this.y, this.z, this.w)
    return new Quat(this.x / l, this.y / l, this.z / l, this.w / l)
  }
  /** Rotates a vector. */
  act(v: Vec3) {
    // v' = v + 2w(u×v) + 2u×(u×v)
    const u = new Vec3(this.x, this.y, this.z)
    const t = u.cross(v).mul(2)
    return v.add(t.mul(this.w)).add(u.cross(t))
  }
}

export const Units = {
  knot: 0.514444,
  foot: 0.3048,
  feetPerMinute: 0.00508,
  g: 9.80665,
}

export const rad = (deg: number) => (deg * Math.PI) / 180
export const deg = (r: number) => (r * 180) / Math.PI
export const clamp = (x: number, lo: number, hi: number) => Math.min(Math.max(x, lo), hi)
export const mix = (a: number, b: number, t: number) => a + (b - a) * t

/** Hermite smoothstep; works for edge0 > edge1 too. */
export function smoothstep(edge0: number, edge1: number, x: number) {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
  return t * t * (3 - 2 * t)
}

/** Swift's truncatingRemainder. */
const trem = (a: number, b: number) => a % b

export function wrap360(d: number) {
  const r = trem(d, 360)
  return r < 0 ? r + 360 : r
}

/** Signed smallest difference a - b in degrees, -180...180. */
export function headingDelta(a: number, b: number) {
  let d = trem(a - b, 360)
  if (d > 180) d -= 360
  if (d < -180) d += 360
  return d
}

/** Body axes follow the renderer: forward -Z, up +Y, right +X. World: north is -Z, east is +X. */
export const Axis = {
  forward: new Vec3(0, 0, -1),
  up: new Vec3(0, 1, 0),
  right: new Vec3(1, 0, 0),
}

export function quatFromEuler(headingDeg: number, pitchDeg: number, bankDeg: number) {
  const yaw = Quat.fromAxisAngle(-rad(headingDeg), Axis.up)
  const pitch = Quat.fromAxisAngle(rad(pitchDeg), Axis.right)
  const roll = Quat.fromAxisAngle(rad(bankDeg), Axis.forward)
  return yaw.mul(pitch).mul(roll).normalized()
}

/** SplitMix64, bit-identical to the Swift SeededRandom. */
export class SeededRandom {
  private state: bigint
  private static readonly mask = (1n << 64n) - 1n
  constructor(seed: number) { this.state = BigInt(seed) & SeededRandom.mask }
  next(): bigint {
    const m = SeededRandom.mask
    this.state = (this.state + 0x9e3779b97f4a7c15n) & m
    let z = this.state
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & m
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & m
    return z ^ (z >> 31n)
  }
  /** Uniform in -1...1. */
  signedUnit() { return (Number(this.next() >> 11n) / 2 ** 53) * 2 - 1 }
}
