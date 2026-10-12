// Port of FlightCore/Environment.swift.
import { Vec3, SeededRandom, clamp, rad, smoothstep } from './math'

export const Atmosphere = {
  seaLevelDensity: 1.225,
  density(altitude: number) {
    const h = Math.max(altitude, -500)
    if (h < 11_000) return 1.225 * Math.pow(1 - 2.25577e-5 * h, 4.2559)
    const d11 = 1.225 * Math.pow(1 - 2.25577e-5 * 11_000, 4.2559)
    return d11 * Math.exp(-(h - 11_000) / 6341.6)
  },
}

/** One airport with runway 36 at the origin, hills, and a canyon cut into mountains to the north. */
export const Terrain = {
  runwayLength: 2400,
  runwayWidth: 45,
  get runwaySouthEnd() { return this.runwayLength / 2 },
  get runwayNorthEnd() { return -this.runwayLength / 2 },

  isOnRunway(x: number, z: number) {
    return Math.abs(x) <= this.runwayWidth / 2 && z <= this.runwaySouthEnd && z >= this.runwayNorthEnd
  },

  canyonCenterX(z: number) { return 1800 * Math.sin(z / 1800) },

  height(x: number, z: number) {
    // Flat around the field and along a corridor 8 km south of it (the runway 36 approach).
    const d = Math.sqrt(x * x + z * z)
    const approach = Math.sqrt(x * x + Math.pow(Math.max(0, z - 8000), 2))
    const airportBlend = smoothstep(2800, 5500, z > 0 ? Math.min(d, approach) : d)

    let h = 120 * (Math.sin(x * 0.0011) * Math.cos(z * 0.0009) + 1)
    h += 60 * (Math.sin(x * 0.0031 + 1.3) * Math.sin(z * 0.0027 + 0.7) + 1)
    h += 25 * Math.sin(x * 0.007 + z * 0.005)

    const north = smoothstep(-4000, -9000, z)
    h += north * (650 + 350 * Math.sin(x * 0.0017) * Math.cos(z * 0.0013) + 120 * Math.sin(x * 0.0061 + z * 0.0043))

    const dx = Math.abs(x - this.canyonCenterX(z))
    const canyon = 1 - smoothstep(160, 520, dx)
    h *= 1 - canyon * north * 0.93

    return Math.max(h * airportBlend, 0)
  },

  normal(x: number, z: number) {
    const e = 2
    const hx = this.height(x + e, z) - this.height(x - e, z)
    const hz = this.height(x, z + e) - this.height(x, z - e)
    return new Vec3(-hx, 2 * e, -hz).normalized()
  },
}

export class WindModel {
  private gust = new Vec3()
  private rng = new SeededRandom(42)
  constructor(public speed = 0, public fromHeadingDeg = 0, public turbulence = 0) {}

  get steady() {
    const toward = rad(this.fromHeadingDeg + 180)
    return new Vec3(Math.sin(toward), 0, -Math.cos(toward)).mul(this.speed)
  }

  sample(dt: number, altitudeAGL: number) {
    if (this.turbulence <= 0) return this.steady
    const sigma = this.turbulence * 3.5 * clamp(altitudeAGL / 150, 0.3, 1)
    const a = dt / 1.2
    const noise = new Vec3(this.rng.signedUnit(), this.rng.signedUnit() * 0.6, this.rng.signedUnit()).mul(sigma * Math.sqrt(2 / a) * 0.5)
    this.gust = this.gust.add(noise.sub(this.gust).mul(a))
    return this.steady.add(this.gust)
  }
}
