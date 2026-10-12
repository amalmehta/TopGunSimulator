import XCTest
import Foundation
@testable import FlightCore

/// Writes reference trajectories for the web port to replay (web/tests/fixtures/golden.json).
/// Runs only when GOLDEN_OUT is set:  GOLDEN_OUT=web/tests/fixtures/golden.json swift test --filter GoldenExport
final class GoldenExportTests: XCTestCase {
    /// The same input scripts live in web/tests/golden.test.ts.
    static func scenarios() -> [(String, Aircraft, Double, (Double, Aircraft) -> PilotInput)] {
        var maneuvers = Aircraft(spec: .trainer)
        maneuvers.placeInFlight(position: Vec3(0, 1000, 0), headingDeg: 0, airspeedKt: 100)
        let cruiseThrottle = maneuvers.state.engine
        var takeoff = Aircraft(spec: .trainer)
        takeoff.placeOnRunway()
        var pull = Aircraft(spec: .fighter)
        pull.placeInFlight(position: Vec3(0, 4000, 0), headingDeg: 0, airspeedKt: 450, gearDown: false)
        var stall = Aircraft(spec: .trainer)
        stall.placeInFlight(position: Vec3(0, 1500, 0), headingDeg: 0, airspeedKt: 80)
        return [
            ("trainer-maneuvers", maneuvers, 12, { t, _ in
                var i = PilotInput(); i.throttle = cruiseThrottle
                i.pitch = t < 1 ? 0.3 : 0
                i.roll = (t >= 2 && t < 3) ? 0.5 : (t >= 5 && t < 6 ? -0.5 : 0)
                i.yaw = (t >= 7 && t < 8) ? 0.6 : 0
                return i }),
            ("trainer-takeoff", takeoff, 30, { _, a in
                var i = PilotInput(); i.throttle = 1
                i.pitch = a.aero.airspeed / Units.knot > 55 ? clamp((9 - a.state.pitchDeg) * 0.06, -0.4, 0.5) : 0
                return i }),
            ("fighter-pull", pull, 6, { t, _ in
                var i = PilotInput(); i.throttle = 1
                i.pitch = t < 3 ? 1 : 0
                i.roll = (t >= 3 && t < 4) ? 1 : 0
                return i }),
            ("trainer-stall", stall, 10, { _, _ in
                var i = PilotInput(); i.throttle = 0; i.pitch = 1
                return i }),
        ]
    }

    func testExportGolden() throws {
        guard let out = ProcessInfo.processInfo.environment["GOLDEN_OUT"] else { throw XCTSkip("set GOLDEN_OUT to export") }
        let dt = 1 / FlightSession.physicsRate
        var result: [String: Any] = [:]
        for (name, start, seconds, script) in Self.scenarios() {
            var a = start
            var samples: [[Double]] = []
            let n = Int((seconds / dt).rounded())
            for i in 0..<n {
                let t = Double(i) * dt
                a.step(dt: dt, input: script(t, a), wind: .zero)
                if (i + 1) % 120 == 0 {
                    let s = a.state
                    samples.append([Double(i + 1) * dt, s.position.x, s.position.y, s.position.z,
                                    s.velocity.x, s.velocity.y, s.velocity.z,
                                    s.orientation.imag.x, s.orientation.imag.y, s.orientation.imag.z, s.orientation.real,
                                    a.aero.alpha, s.crashed ? 1 : 0])
                }
            }
            result[name] = samples
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: out))
    }
}
