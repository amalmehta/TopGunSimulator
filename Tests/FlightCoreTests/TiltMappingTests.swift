import XCTest
import simd
@testable import FlightCore

final class TiltMappingTests: XCTestCase {
    /// Gravity (pointing down, controller axes: x right, y up out of the face, z toward the player)
    /// for a controller pitched far-edge-up by `pitch` and rolled right-side-down by `roll`.
    private func gravity(pitch: Double, roll: Double) -> Vec3 {
        let p = pitch.radians, r = roll.radians
        return Vec3(sin(r), -cos(p) * cos(r), sin(p) * cos(r))
    }

    func testNeutralHoldIsCentred() {
        let held = gravity(pitch: 20, roll: 0)
        let n = TiltMapping.calibrate(held)
        let a = TiltMapping.axes(held, neutral: n)
        XCTAssertEqual(a.roll, 0); XCTAssertEqual(a.pitch, 0)
    }

    func testDirections() {
        let n = TiltMapping.calibrate(gravity(pitch: 20, roll: 0))
        XCTAssertGreaterThan(TiltMapping.axes(gravity(pitch: 35, roll: 0), neutral: n).pitch, 0.4)   // far edge up = nose up
        XCTAssertLessThan(TiltMapping.axes(gravity(pitch: 5, roll: 0), neutral: n).pitch, -0.4)
        XCTAssertGreaterThan(TiltMapping.axes(gravity(pitch: 20, roll: 15), neutral: n).roll, 0.4)   // right side down = roll right
        XCTAssertLessThan(TiltMapping.axes(gravity(pitch: 20, roll: -15), neutral: n).roll, -0.4)
    }

    func testRangeDeadZoneAndInvert() {
        let n = TiltMapping.calibrate(gravity(pitch: 20, roll: 0))
        XCTAssertEqual(TiltMapping.axes(gravity(pitch: 20, roll: 15), neutral: n, rangeDeg: 15).roll, 1, accuracy: 1e-6)
        let tip = gravity(pitch: 20, roll: 12)
        XCTAssertGreaterThan(TiltMapping.axes(tip, neutral: n, rangeDeg: 15).roll, TiltMapping.axes(tip, neutral: n, rangeDeg: 60).roll)
        let wobble = TiltMapping.axes(gravity(pitch: 21, roll: 1), neutral: n)
        XCTAssertEqual(wobble.roll, 0); XCTAssertEqual(wobble.pitch, 0)
        let up = gravity(pitch: 35, roll: 0)
        XCTAssertEqual(TiltMapping.axes(up, neutral: n, invertPitch: true).pitch, -TiltMapping.axes(up, neutral: n).pitch, accuracy: 1e-12)
    }

    func testMagnitudeDoesNotMatter() {
        let n = TiltMapping.calibrate(gravity(pitch: 20, roll: 0) * 9.81)
        let a = TiltMapping.axes(gravity(pitch: 35, roll: 10), neutral: n)
        let b = TiltMapping.axes(gravity(pitch: 35, roll: 10) * 9.81, neutral: TiltMapping.calibrate(gravity(pitch: 20, roll: 0)))
        XCTAssertEqual(a.roll, b.roll, accuracy: 1e-9); XCTAssertEqual(a.pitch, b.pitch, accuracy: 1e-9)
    }
}
