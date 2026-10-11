import Foundation
import simd

/// International Standard Atmosphere (troposphere + lower stratosphere).
public enum Atmosphere {
    public static let seaLevelDensity = 1.225

    public static func density(altitude h: Double) -> Double {
        let h = max(h, -500)
        if h < 11_000 {
            return seaLevelDensity * pow(1 - 2.25577e-5 * h, 4.2559)
        }
        let d11 = seaLevelDensity * pow(1 - 2.25577e-5 * 11_000, 4.2559)
        return d11 * exp(-(h - 11_000) / 6341.6)
    }
}

/// The world: one airport with a north-south runway at the origin, rolling hills,
/// and a mountain range to the north cut by a winding canyon (the low-level route).
public enum Terrain {
    /// Runway 36: threshold at the south end, aircraft depart heading north (-Z).
    public static let runwayLength = 2400.0
    public static let runwayWidth = 45.0
    public static var runwaySouthEnd: Double { runwayLength / 2 }   // z of the runway 36 threshold
    public static var runwayNorthEnd: Double { -runwayLength / 2 }

    public static func isOnRunway(x: Double, z: Double) -> Bool {
        abs(x) <= runwayWidth / 2 && z <= runwaySouthEnd && z >= runwayNorthEnd
    }

    /// Canyon centreline x for a given z (the canyon runs north from z = -6 km).
    public static func canyonCenterX(z: Double) -> Double { 1800 * sin(z / 1800) }

    /// How "mountainous" a location is (0 near the airport, 1 deep in the range to the north).
    static func mountainFactor(z: Double) -> Double { smoothstep(-4000, -9000, z) }

    /// Ground height in metres above sea level. Flat (0 m) around the airport.
    public static func height(x: Double, z: Double) -> Double {
        // Flat around the field and along a corridor 8 km south of it (the runway 36 approach).
        let d = (x * x + z * z).squareRoot()
        let approach = (x * x + pow(max(0, z - 8000), 2)).squareRoot()
        let airportBlend = smoothstep(2800, 5500, z > 0 ? min(d, approach) : d)

        var h = 120 * (sin(x * 0.0011) * cos(z * 0.0009) + 1)
        h += 60 * (sin(x * 0.0031 + 1.3) * sin(z * 0.0027 + 0.7) + 1)
        h += 25 * sin(x * 0.007 + z * 0.005)

        let north = mountainFactor(z: z)
        h += north * (650 + 350 * sin(x * 0.0017) * cos(z * 0.0013) + 120 * sin(x * 0.0061 + z * 0.0043))

        let dx = abs(x - canyonCenterX(z: z))
        let canyon = 1 - smoothstep(160, 520, dx)
        h *= 1 - canyon * north * 0.93

        return max(h * airportBlend, 0)
    }

    /// Approximate surface normal (finite differences).
    public static func normal(x: Double, z: Double) -> Vec3 {
        let e = 2.0
        let hx = height(x: x + e, z: z) - height(x: x - e, z: z)
        let hz = height(x: x, z: z + e) - height(x: x, z: z - e)
        return simd_normalize(Vec3(-hx, 2 * e, -hz))
    }
}

/// Steady wind plus optional turbulence.
public struct WindModel {
    public var speed: Double = 0          // m/s
    public var fromHeadingDeg: Double = 0 // direction the wind blows FROM
    public var turbulence: Double = 0     // 0...1
    private var gust = Vec3.zero
    private var rng = SeededRandom(seed: 42)

    public init(speed: Double = 0, fromHeadingDeg: Double = 0, turbulence: Double = 0) {
        self.speed = speed
        self.fromHeadingDeg = fromHeadingDeg
        self.turbulence = turbulence
    }

    public var steady: Vec3 {
        // Wind from heading H blows toward H + 180.
        let toward = (fromHeadingDeg + 180).radians
        return Vec3(sin(toward), 0, -cos(toward)) * speed
    }

    /// Advances the gust state (first-order filtered noise) and returns the wind at this instant.
    public mutating func sample(dt: Double, altitudeAGL: Double) -> Vec3 {
        guard turbulence > 0 else { return steady }
        let sigma = turbulence * 3.5 * clamp(altitudeAGL / 150, 0.3, 1)
        let tau = 1.2
        let a = dt / tau
        let noise = Vec3(rng.signedUnit(), rng.signedUnit() * 0.6, rng.signedUnit()) * sigma * (2 / a).squareRoot() * 0.5
        gust += (noise - gust) * a
        return steady + gust
    }
}
