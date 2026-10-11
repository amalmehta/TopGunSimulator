import Foundation
import simd

public typealias Vec3 = SIMD3<Double>
public typealias Quat = simd_quatd

/// Unit conversions. Everything inside FlightCore is SI (metres, seconds, kilograms, radians).
public enum Units {
    public static let knot = 0.514444          // m/s
    public static let foot = 0.3048            // m
    public static let feetPerMinute = 0.00508  // m/s
    public static let g = 9.80665              // m/s²
}

public extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

@inlinable public func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { min(max(x, lo), hi) }

@inlinable public func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// Hermite smoothstep; works for edge0 > edge1 too (reversed ramp).
@inlinable public func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}

/// Wraps an angle in degrees to 0..<360.
@inlinable public func wrap360(_ deg: Double) -> Double {
    let r = deg.truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}

/// Signed smallest difference a - b in degrees, in -180...180.
@inlinable public func headingDelta(_ a: Double, _ b: Double) -> Double {
    var d = (a - b).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}

/// Body axes follow SceneKit's node convention so the renderer can use the orientation directly:
/// forward is -Z, up is +Y, right is +X. World: +Y up, north is -Z, east is +X.
public enum Axis {
    public static let forward = Vec3(0, 0, -1)
    public static let up = Vec3(0, 1, 0)
    public static let right = Vec3(1, 0, 0)
}

public extension Quat {
    static let identity = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)

    /// Orientation from heading (deg, 0 = north, clockwise), pitch (deg, nose up +) and bank (deg, right wing down +).
    static func fromEuler(headingDeg: Double, pitchDeg: Double, bankDeg: Double) -> Quat {
        let yaw = simd_quatd(angle: -headingDeg.radians, axis: Axis.up)
        let pitch = simd_quatd(angle: pitchDeg.radians, axis: Axis.right)
        let roll = simd_quatd(angle: bankDeg.radians, axis: Axis.forward)
        return (yaw * pitch * roll).normalized
    }
}

/// Small deterministic RNG (SplitMix64) so turbulence and AI are reproducible in tests.
public struct SeededRandom {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform in -1...1.
    public mutating func signedUnit() -> Double { Double(next() >> 11) / Double(1 << 53) * 2 - 1 }
}
