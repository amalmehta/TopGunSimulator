import XCTest
@testable import FlightCore

final class OnScreenControlsTests: XCTestCase {
    func testStickCentreAndDeadZone() {
        let c = OnScreenControls.stickAxes(dx: 0, dy: 0, radius: 60)
        XCTAssertEqual(c.roll, 0); XCTAssertEqual(c.pitch, 0)
        let tiny = OnScreenControls.stickAxes(dx: 3, dy: -3, radius: 60)
        XCTAssertEqual(tiny.roll, 0); XCTAssertEqual(tiny.pitch, 0)
    }

    func testStickDirectionsAndRim() {
        XCTAssertEqual(OnScreenControls.stickAxes(dx: 0, dy: 60, radius: 60).pitch, 1, accuracy: 1e-9)   // drag down = nose up
        XCTAssertEqual(OnScreenControls.stickAxes(dx: 0, dy: -60, radius: 60).pitch, -1, accuracy: 1e-9)
        XCTAssertEqual(OnScreenControls.stickAxes(dx: 60, dy: 0, radius: 60).roll, 1, accuracy: 1e-9)
        let diag = OnScreenControls.stickAxes(dx: 200, dy: 200, radius: 60)
        XCTAssertEqual(diag.roll, diag.pitch, accuracy: 1e-9)
        XCTAssertLessThanOrEqual((diag.roll * diag.roll + diag.pitch * diag.pitch).squareRoot(), 2.0.squareRoot())
    }

    func testApplyMergesAndConsumesThrottle() {
        var c = OnScreenControls()
        c.active = true; c.stickHeld = true; c.pitch = 0.5; c.roll = -0.25; c.yaw = 1; c.throttle = 0.8; c.brakes = true; c.trigger = true
        var input = PilotInput(); var throttle = 0.2
        c.apply(to: &input, throttle: &throttle, sensitivity: 1)
        XCTAssertEqual(input.pitch, 0.5); XCTAssertEqual(input.roll, -0.25); XCTAssertEqual(input.yaw, 1)
        XCTAssertEqual(throttle, 0.8); XCTAssertEqual(input.brakes, 1); XCTAssertTrue(input.trigger)
        XCTAssertNil(c.throttle, "slider value is consumed; throttle stays where it was left")
    }

    func testInactiveIsIgnoredAndIdleStickLeavesKeyboardAlone() {
        var off = OnScreenControls(); off.pitch = 1; off.throttle = 1; off.trigger = true
        var input = PilotInput(); var throttle = 0.0
        off.apply(to: &input, throttle: &throttle, sensitivity: 1)
        XCTAssertEqual(input.pitch, 0); XCTAssertEqual(throttle, 0); XCTAssertFalse(input.trigger)

        var idle = OnScreenControls(); idle.active = true
        var kb = PilotInput(); kb.pitch = 0.4; kb.roll = 0.3
        idle.apply(to: &kb, throttle: &throttle, sensitivity: 1)
        XCTAssertEqual(kb.pitch, 0.4); XCTAssertEqual(kb.roll, 0.3)
    }
}
