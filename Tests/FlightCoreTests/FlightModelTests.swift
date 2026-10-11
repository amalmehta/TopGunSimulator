import XCTest
import simd
@testable import FlightCore

/// Runs one aircraft for `seconds` with a fixed input.
private func fly(_ a: inout Aircraft, seconds: Double, input: PilotInput, wind: Vec3 = .zero) {
    let dt = 1 / FlightSession.physicsRate
    for _ in 0..<Int(seconds / dt) { a.step(dt: dt, input: input, wind: wind) }
}

final class AtmosphereAndTerrainTests: XCTestCase {
    func testStandardAtmosphere() {
        XCTAssertEqual(Atmosphere.density(altitude: 0), 1.225, accuracy: 1e-6)
        XCTAssertEqual(Atmosphere.density(altitude: 3048), 0.905, accuracy: 0.01)   // 10,000 ft
        XCTAssertEqual(Atmosphere.density(altitude: 11_000), 0.364, accuracy: 0.01)
    }

    func testAirportIsFlatAndCanyonIsLowerThanItsWalls() {
        XCTAssertEqual(Terrain.height(x: 0, z: 0), 0)
        XCTAssertEqual(Terrain.height(x: 20, z: 1100), 0)
        let z = -11_000.0
        let center = Terrain.canyonCenterX(z: z)
        XCTAssertLessThan(Terrain.height(x: center, z: z) + 300, Terrain.height(x: center + 900, z: z))
    }

    func testEulerRoundTrip() {
        var s = AircraftState()
        s.orientation = .fromEuler(headingDeg: 135, pitchDeg: 10, bankDeg: 20)
        XCTAssertEqual(s.headingDeg, 135, accuracy: 0.01)
        XCTAssertEqual(s.pitchDeg, 10, accuracy: 0.01)
        XCTAssertEqual(s.bankDeg, 20, accuracy: 0.01)
    }
}

final class FlightModelTests: XCTestCase {
    func testTrimmedTrainerHoldsAltitudeHandsOff() {
        var a = Aircraft(spec: .trainer)
        a.placeInFlight(position: Vec3(0, 1000, 0), headingDeg: 0, airspeedKt: 100)
        var input = PilotInput(); input.throttle = a.state.engine
        fly(&a, seconds: 30, input: input)
        XCTAssertFalse(a.state.crashed)
        XCTAssertEqual(a.state.position.y, 1000, accuracy: 60, "phugoid should stay small when trimmed")
        XCTAssertEqual(a.state.bankDeg, 0, accuracy: 5)
        XCTAssertEqual(a.aero.airspeed / Units.knot, 100, accuracy: 12)
    }

    func testStickBackPitchesUpAndStickRightRollsRight() {
        var a = Aircraft(spec: .trainer)
        a.placeInFlight(position: Vec3(0, 1000, 0), headingDeg: 0, airspeedKt: 100)
        var input = PilotInput(); input.throttle = a.state.engine; input.pitch = 0.3
        fly(&a, seconds: 1.5, input: input)
        XCTAssertGreaterThan(a.state.pitchDeg, 5)

        a.placeInFlight(position: Vec3(0, 1000, 0), headingDeg: 0, airspeedKt: 100)
        input.pitch = 0; input.roll = 0.6
        fly(&a, seconds: 1.0, input: input)
        XCTAssertGreaterThan(a.state.bankDeg, 20)
    }

    func testBankedTurnChangesHeadingTheRightWay() {
        var a = Aircraft(spec: .trainer)
        a.placeInFlight(position: Vec3(0, 1000, 0), headingDeg: 0, airspeedKt: 100)
        var input = PilotInput(); input.throttle = a.state.engine; input.roll = 0.5
        fly(&a, seconds: 0.6, input: input)
        input.roll = 0; input.pitch = 0.08
        fly(&a, seconds: 8, input: input)
        XCTAssertGreaterThan(a.state.headingDeg, 20)
        XCTAssertLessThan(a.state.headingDeg, 200)
    }

    func testLiftCurveStalls() {
        let s = AircraftSpec.trainer
        let atStall = Aircraft.liftCoefficient(spec: s, alpha: s.stallAlpha, flaps: 0)
        let past = Aircraft.liftCoefficient(spec: s, alpha: s.stallAlpha + 8.radians, flaps: 0)
        XCTAssertGreaterThan(atStall, 1.4)
        XCTAssertLessThan(past, atStall * 0.85)
        XCTAssertGreaterThan(Aircraft.liftCoefficient(spec: s, alpha: 5.radians, flaps: 1),
                             Aircraft.liftCoefficient(spec: s, alpha: 5.radians, flaps: 0))
    }

    func testFullAftStickAtIdleStallsTheTrainer() {
        var a = Aircraft(spec: .trainer)
        a.placeInFlight(position: Vec3(0, 1500, 0), headingDeg: 0, airspeedKt: 80)
        var input = PilotInput(); input.throttle = 0; input.pitch = 1
        var stalled = false
        let dt = 1 / FlightSession.physicsRate
        for _ in 0..<Int(15 / dt) {
            a.step(dt: dt, input: input, wind: .zero)
            if a.aero.stalled { stalled = true; break }
        }
        XCTAssertTrue(stalled)
        // Recovery: stick forward, full power.
        input.pitch = -0.3; input.throttle = 1
        fly(&a, seconds: 4, input: input)
        XCTAssertFalse(a.aero.stalled)
        XCTAssertFalse(a.state.crashed)
    }

    func testTrainerTakesOffWithFullPower() {
        var a = Aircraft(spec: .trainer)
        a.placeOnRunway()
        var input = PilotInput(); input.throttle = 1
        let dt = 1 / FlightSession.physicsRate
        var liftoffZ: Double?
        for _ in 0..<Int(60 / dt) {
            input.pitch = a.aero.airspeed / Units.knot > 55 ? clamp((9 - a.state.pitchDeg) * 0.06, -0.4, 0.5) : 0
            a.step(dt: dt, input: input, wind: .zero)
            if a.state.wheelsOnGround == 0 && a.state.position.y > 5 && liftoffZ == nil { liftoffZ = a.state.position.z }
            XCTAssertFalse(a.state.crashed, a.state.crashReason ?? "")
            if a.state.crashed { return }
        }
        let z = try! XCTUnwrap(liftoffZ)
        let roll = Terrain.runwaySouthEnd - 60 - z
        XCTAssertLessThan(roll, 800, "ground roll \(roll) m")
        XCTAssertLessThan(abs(a.state.position.x), 60, "auto-rudder tracked the centreline")
        XCTAssertGreaterThan(a.state.position.y, 100)
    }

    func testAircraftSitsStillOnRunway() {
        for spec in [AircraftSpec.trainer, .fighter] {
            var a = Aircraft(spec: spec)
            a.placeOnRunway()
            var input = PilotInput(); input.brakes = 1
            fly(&a, seconds: 5, input: input)
            XCTAssertFalse(a.state.crashed, "\(spec.name): \(a.state.crashReason ?? "")")
            XCTAssertEqual(a.state.wheelsOnGround, 3, spec.name)
            XCTAssertLessThan(simd_length(a.state.velocity), 0.3, spec.name)
            XCTAssertEqual(a.state.pitchDeg, 0, accuracy: 2, spec.name)
        }
    }

    func testFighterTakesOffAndRetractsGear() {
        var a = Aircraft(spec: .fighter)
        a.placeOnRunway()
        var input = PilotInput(); input.throttle = 1
        let dt = 1 / FlightSession.physicsRate
        for _ in 0..<Int(40 / dt) {
            input.pitch = a.aero.airspeed / Units.knot > 150 ? clamp((10 - a.state.pitchDeg) * 0.08, -0.4, 0.6) : 0
            a.step(dt: dt, input: input, wind: .zero)
            if a.state.crashed { XCTFail(a.state.crashReason ?? ""); return }
        }
        XCTAssertGreaterThan(a.state.position.y, 150)
        a.toggleGear()
        XCTAssertFalse(a.state.gearDown)
    }

    func testFighterGLimiter() {
        var a = Aircraft(spec: .fighter)
        a.placeInFlight(position: Vec3(0, 4000, 0), headingDeg: 0, airspeedKt: 450, gearDown: false)
        var input = PilotInput(); input.throttle = 1; input.pitch = 1
        var maxG = 0.0
        let dt = 1 / FlightSession.physicsRate
        for _ in 0..<Int(4 / dt) {
            a.step(dt: dt, input: input, wind: .zero)
            maxG = max(maxG, a.state.loadFactor)
        }
        XCTAssertGreaterThan(maxG, 6)
        XCTAssertLessThan(maxG, 9.0)
    }

    func testTrimmedFighterHoldsAltitude() {
        var a = Aircraft(spec: .fighter)
        a.placeInFlight(position: Vec3(0, 3000, 0), headingDeg: 0, airspeedKt: 380, gearDown: false)
        var input = PilotInput(); input.throttle = a.state.engine
        fly(&a, seconds: 20, input: input)
        XCTAssertEqual(a.state.position.y, 3000, accuracy: 150)
        XCTAssertEqual(a.state.bankDeg, 0, accuracy: 5)
    }

    func testHardLandingCrashesAndGentleOneDoesNot() {
        var a = Aircraft(spec: .trainer)
        a.placeInFlight(position: Vec3(0, 2, 0), headingDeg: 0, airspeedKt: 55, flaps: 1)
        a.state.velocity.y = -1.0
        var input = PilotInput(); input.throttle = 0
        fly(&a, seconds: 3, input: input)
        XCTAssertFalse(a.state.crashed, a.state.crashReason ?? "")
        XCTAssertNotNil(a.lastTouchdown)

        a.placeInFlight(position: Vec3(0, 5, 0), headingDeg: 0, airspeedKt: 60, flaps: 1)
        a.state.velocity.y = -8
        fly(&a, seconds: 2, input: input)
        XCTAssertTrue(a.state.crashed)
    }
}

final class SessionTests: XCTestCase {
    func testLessonStepsAdvance() {
        var session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: "controls")!))
        XCTAssertEqual(session.lesson?.stepIndex, 0)
        session.input.pitch = 0.4
        for _ in 0..<240 { session.advance(by: 1 / 60) }
        XCTAssertGreaterThanOrEqual(session.lesson?.stepIndex ?? 0, 1)
    }

    func testStepsWaitForTheirCondition() {
        for id in ["dogfight", "canyon-run", "landing", "takeoff"] {
            var session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: id)!))
            for _ in 0..<60 { session.advance(by: 1 / 60) }
            XCTAssertEqual(session.lesson?.stepIndex, 0, "\(id) advanced without meeting its goal")
        }
    }

    func testScriptedPilotPassesTakeoffLesson() {
        var session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: "takeoff")!))
        session.input.throttle = 1
        for _ in 0..<(60 * 90) {
            let t = session.telemetry
            session.input.pitch = t.airspeedKt > 55 ? clamp((9 - t.pitchDeg) * 0.06, -0.4, 0.5) : 0
            session.advance(by: 1 / 60)
            if session.outcome != .running { break }
        }
        XCTAssertEqual(session.outcome, .passed)
    }

    func testScriptedPilotPassesControlsLesson() {
        var session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: "controls")!))
        for _ in 0..<(60 * 120) {
            let t = session.telemetry
            var i = PilotInput()
            i.throttle = session.input.throttle
            switch session.lesson!.stepIndex {
            case 0: i.pitch = clamp((12 - t.pitchDeg) * 0.05, -0.5, 0.5)
            case 1: i.pitch = clamp((-6 - t.pitchDeg) * 0.05, -0.5, 0.5)
            case 2: i.pitch = clamp((0 - t.pitchDeg) * 0.05, -0.5, 0.5)
            case 3: i.roll = clamp((-30 - t.bankDeg) * 0.03, -0.6, 0.6); i.pitch = 0.05
            case 4: i.roll = clamp((30 - t.bankDeg) * 0.03, -0.6, 0.6); i.pitch = 0.05
            case 5: i.roll = clamp(-t.bankDeg * 0.03, -0.6, 0.6); i.pitch = clamp(-t.pitchDeg * 0.05, -0.5, 0.5)
            case 6: i.yaw = 1
            case 7: i.throttle = 0
            default: i.throttle = 1
            }
            session.input = i
            session.advance(by: 1 / 60)
            if session.outcome != .running { break }
        }
        XCTAssertEqual(session.outcome, .passed, "stuck at step \(session.lesson!.stepIndex)")
    }

    func testLandingApproachIsOverFlatGround() {
        for z in stride(from: Terrain.runwaySouthEnd, through: Terrain.runwaySouthEnd + 6000, by: 250) {
            XCTAssertEqual(Terrain.height(x: 0, z: z), 0, "terrain at z=\(z)")
        }
    }

    func testCrashFailsLesson() {
        var session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: "controls")!))
        session.input.throttle = 1
        var events: [SessionEvent] = []
        for _ in 0..<(60 * 90) {
            session.input.pitch = clamp((-30 - session.telemetry.pitchDeg) * 0.03, -0.5, 0.5)
            session.advance(by: 1 / 60)
            events += session.drainEvents()
            if case .failed = session.outcome { break }
        }
        XCTAssertTrue(events.contains { if case .crashed = $0 { return true }; return false })
        if case .failed = session.outcome {} else { XCTFail("expected failure, got \(String(describing: session.outcome))") }
    }

    func testGateCrossing() {
        var session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: "canyon-run")!))
        let g = session.gates[0]
        session.updateGates(from: g.center - g.normal * 5, to: g.center + g.normal * 5)
        XCTAssertEqual(session.gates[0].status, .passed)
        let g2 = session.gates[1]
        session.updateGates(from: g2.center - g2.normal * 5 + Vec3(0, 200, 0), to: g2.center + g2.normal * 5 + Vec3(0, 200, 0))
        XCTAssertEqual(session.gates[1].status, .missed)
    }

    func testCanyonStartIsClearOfTerrain() {
        let session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: "canyon-run")!))
        XCTAssertGreaterThan(session.telemetry.aglFt, 500)
        for g in session.gates {
            XCTAssertGreaterThan(g.center.y - g.radius, Terrain.height(x: g.center.x, z: g.center.z), "gate \(g.id) clears the floor")
        }
    }

    func testGunsOnTarget() {
        var shooter = AircraftState()
        shooter.position = .zero
        var target = AircraftState()
        target.position = Vec3(0, 0, -500)
        XCTAssertTrue(FlightSession.onTarget(shooter: shooter, target: target, cone: 1.radians, range: 1000))
        target.position = Vec3(100, 0, -500)
        XCTAssertFalse(FlightSession.onTarget(shooter: shooter, target: target, cone: 1.radians, range: 1000))
    }

    func testBanditEngagesAndSurvivesOnItsOwn() {
        var session = FlightSession(mode: .lesson(LessonCatalog.lesson(id: "dogfight")!))
        session.input.throttle = 0.9
        let startRange = session.banditDistance!
        var minRange = startRange
        for _ in 0..<(60 * 40) {
            session.advance(by: 1 / 60)
            minRange = min(minRange, session.banditDistance!)
        }
        XCTAssertLessThan(minRange, 1500, "bandit should close for the merge")
        XCTAssertFalse(session.bandit!.state.crashed, session.bandit!.state.crashReason ?? "")
    }

    func testInstructorFlagsStall() {
        var t = Telemetry()
        t.stalled = true
        t.alphaDeg = 18
        var instructor = Instructor()
        let hints = instructor.evaluate(t, spec: .trainer, dt: 0.1)
        XCTAssertEqual(hints.first?.id, "stall")
    }

    func testEveryLessonStartsCleanly() {
        for lesson in LessonCatalog.all {
            var session = FlightSession(mode: .lesson(lesson))
            for _ in 0..<120 { session.advance(by: 1 / 60) }
            XCTAssertFalse(session.player.state.crashed, "\(lesson.title): \(session.player.state.crashReason ?? "")")
            if case .failed(let r) = session.outcome { XCTFail("\(lesson.title) failed at start: \(r)") }
        }
    }
}
