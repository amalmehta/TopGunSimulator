import Foundation

/// A landing-gear or structural contact point in body coordinates.
public struct ContactPoint {
    public enum Kind { case noseGear, mainGear, airframe }
    public var name: String
    public var position: Vec3
    public var kind: Kind
}

/// Everything the flight model needs to know about one aircraft type.
/// Control derivatives are per unit of normalised control deflection (-1...1).
public struct AircraftSpec {
    public enum Kind: String, CaseIterable, Identifiable, Codable {
        case trainer, fighter
        public var id: String { rawValue }
    }

    public var kind: Kind
    public var name: String
    public var shortName: String

    // Mass and geometry
    public var mass: Double
    public var inertia: Vec3          // (pitch, yaw, roll) i.e. about body x, y, z
    public var wingArea: Double
    public var wingSpan: Double
    public var chord: Double

    // Lift and drag
    public var cl0: Double
    public var clAlpha: Double
    public var stallAlpha: Double     // rad, clean
    public var cd0: Double
    public var inducedDragK: Double
    public var flapCL: Double         // at full flaps
    public var flapCD: Double
    public var flapStallReduction: Double
    public var gearCD: Double
    public var cyBeta: Double
    public var cyRudder: Double

    // Moments
    public var cm0: Double
    public var cmAlpha: Double
    public var cmQ: Double
    public var cmElevator: Double
    public var cmFlaps: Double
    public var clBeta: Double         // roll due to sideslip (dihedral effect)
    public var clP: Double
    public var clR: Double
    public var clAileron: Double
    public var cnBeta: Double
    public var cnR: Double
    public var cnRudder: Double
    public var cnAileron: Double      // adverse yaw

    // Propulsion
    public var isJet: Bool
    public var staticThrust: Double   // prop: static thrust; jet: military (non-afterburner) thrust
    public var afterburnerThrust: Double
    public var propZeroThrustSpeed: Double
    public var engineSpoolTime: Double
    public var propTurningTendency: Double // N·m of left yaw at full power and low speed

    // Systems
    public var hasRetractableGear: Bool
    public var flapDetents: [Double]  // in degrees, for display
    public var flyByWire: Bool
    public var gLimit: Double
    public var alphaLimit: Double     // rad, for fly-by-wire
    public var maxRollRate: Double    // rad/s, for fly-by-wire
    public var trimRange: Double

    // Ground handling
    public var contacts: [ContactPoint]
    public var gearStiffness: Double
    public var gearDamping: Double
    public var maxSinkRate: Double    // m/s, harder than this at touchdown = crash
    public var noseSteerAngle: Double // rad

    // Reference speeds (knots) used by instructor and lessons
    public var vStallKt: Double
    public var vRotateKt: Double
    public var vClimbKt: Double
    public var vApproachKt: Double
    public var vCruiseKt: Double
    public var vNeKt: Double

    public var weight: Double { mass * Units.g }
    public func stallAlpha(flaps: Double) -> Double { stallAlpha - flapStallReduction * flaps }
}

public extension AircraftSpec {
    static func of(_ kind: Kind) -> AircraftSpec { kind == .trainer ? .trainer : .fighter }

    /// A Cessna 172-like high-wing trainer. Derivatives loosely based on published C172 data.
    static let trainer = AircraftSpec(
        kind: .trainer, name: "Skyhawk Trainer", shortName: "Trainer",
        mass: 1000, inertia: Vec3(1825, 2667, 1285),
        wingArea: 16.2, wingSpan: 11.0, chord: 1.5,
        cl0: 0.25, clAlpha: 4.8, stallAlpha: 15.radians,
        cd0: 0.028, inducedDragK: 0.054,
        flapCL: 0.55, flapCD: 0.05, flapStallReduction: 2.radians, gearCD: 0,
        cyBeta: -0.31, cyRudder: 0.06,
        cm0: 0.0, cmAlpha: -1.0, cmQ: -12.4, cmElevator: 0.55, cmFlaps: -0.04,
        clBeta: -0.089, clP: -0.47, clR: 0.096, clAileron: 0.045,
        cnBeta: 0.065, cnR: -0.099, cnRudder: 0.025, cnAileron: -0.006,
        isJet: false, staticThrust: 3000, afterburnerThrust: 0, propZeroThrustSpeed: 100,
        engineSpoolTime: 0.4, propTurningTendency: 420,
        hasRetractableGear: false, flapDetents: [0, 10, 20, 30],
        flyByWire: false, gLimit: 3.8, alphaLimit: 0, maxRollRate: 0, trimRange: 0.35,
        contacts: [
            ContactPoint(name: "Nose wheel", position: Vec3(0, -1.3, -1.6), kind: .noseGear),
            ContactPoint(name: "Left main", position: Vec3(-1.25, -1.3, 0.35), kind: .mainGear),
            ContactPoint(name: "Right main", position: Vec3(1.25, -1.3, 0.35), kind: .mainGear),
            ContactPoint(name: "Left wingtip", position: Vec3(-5.5, 0.9, 0.3), kind: .airframe),
            ContactPoint(name: "Right wingtip", position: Vec3(5.5, 0.9, 0.3), kind: .airframe),
            ContactPoint(name: "Tail", position: Vec3(0, -0.2, 5.2), kind: .airframe),
            ContactPoint(name: "Propeller", position: Vec3(0, -0.85, -2.3), kind: .airframe),
        ],
        gearStiffness: 36_000, gearDamping: 5_200, maxSinkRate: 4.0, noseSteerAngle: 25.radians,
        vStallKt: 48, vRotateKt: 55, vClimbKt: 75, vApproachKt: 65, vCruiseKt: 115, vNeKt: 163
    )

    /// An F/A-18-like twin-engine fighter with a simple fly-by-wire system.
    static let fighter = AircraftSpec(
        kind: .fighter, name: "Hornet Fighter", shortName: "Fighter",
        mass: 16_000, inertia: Vec3(205_000, 230_000, 31_000),
        wingArea: 38.0, wingSpan: 12.3, chord: 3.5,
        cl0: 0.05, clAlpha: 3.6, stallAlpha: 32.radians,
        cd0: 0.022, inducedDragK: 0.12,
        flapCL: 0.5, flapCD: 0.04, flapStallReduction: 0, gearCD: 0.025,
        cyBeta: -0.8, cyRudder: 0.12,
        cm0: 0.0, cmAlpha: -0.45, cmQ: -6.0, cmElevator: 0.5, cmFlaps: -0.02,
        clBeta: -0.08, clP: -0.35, clR: 0.1, clAileron: 0.06,
        cnBeta: 0.12, cnR: -0.35, cnRudder: 0.045, cnAileron: -0.004,
        isJet: true, staticThrust: 110_000, afterburnerThrust: 158_000, propZeroThrustSpeed: 0,
        engineSpoolTime: 1.6, propTurningTendency: 0,
        hasRetractableGear: true, flapDetents: [0, 15, 30],
        flyByWire: true, gLimit: 7.5, alphaLimit: 25.radians, maxRollRate: 3.5, trimRange: 0.25,
        contacts: [
            ContactPoint(name: "Nose wheel", position: Vec3(0, -2.0, -5.5), kind: .noseGear),
            ContactPoint(name: "Left main", position: Vec3(-1.6, -2.0, 0.8), kind: .mainGear),
            ContactPoint(name: "Right main", position: Vec3(1.6, -2.0, 0.8), kind: .mainGear),
            ContactPoint(name: "Left wingtip", position: Vec3(-6.1, 0.0, 2.0), kind: .airframe),
            ContactPoint(name: "Right wingtip", position: Vec3(6.1, 0.0, 2.0), kind: .airframe),
            ContactPoint(name: "Tail", position: Vec3(0, -0.5, 7.8), kind: .airframe),
            ContactPoint(name: "Nose", position: Vec3(0, -0.6, -8.5), kind: .airframe),
            ContactPoint(name: "Belly", position: Vec3(0, -1.1, 0), kind: .airframe),
        ],
        gearStiffness: 420_000, gearDamping: 60_000, maxSinkRate: 7.0, noseSteerAngle: 20.radians,
        vStallKt: 110, vRotateKt: 150, vClimbKt: 350, vApproachKt: 155, vCruiseKt: 450, vNeKt: 750
    )
}
