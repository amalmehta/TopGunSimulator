import Foundation
import simd

// MARK: - Canyon route

public struct Gate: Identifiable {
    public enum Status { case pending, passed, missed }
    public var id: Int
    public var center: Vec3
    public var normal: Vec3       // direction of travel through the gate
    public var radius: Double
    public var status = Status.pending
}

public enum CanyonRoute {
    public static let firstZ = -7000.0
    public static let gateSpacing = 900.0
    public static let gateCount = 12

    /// Direction of travel along the canyon centreline at z (heading north).
    static func tangent(z: Double) -> Vec3 {
        let dxdz = cos(z / 1800)                 // derivative of 1800·sin(z/1800)
        return simd_normalize(Vec3(-dxdz, 0, -1)) // moving toward -z
    }

    public static func gates() -> [Gate] {
        (0..<gateCount).map { i in
            let z = firstZ - Double(i) * gateSpacing
            let x = Terrain.canyonCenterX(z: z)
            let floor = Terrain.height(x: x, z: z)
            return Gate(id: i, center: Vec3(x, floor + 70, z), normal: tangent(z: z), radius: 40)
        }
    }

    public static var start: LessonStart {
        let z = -4200.0
        let t = tangent(z: z)
        let heading = wrap360(atan2(t.x, -t.z).degrees)
        let x = Terrain.canyonCenterX(z: z)
        return .air(x: x, altitudeFt: (Terrain.height(x: x, z: z) + 260) / Units.foot, z: z, headingDeg: heading, speedKt: 360, flaps: 0, gearDown: false)
    }
}

// MARK: - Bandit AI

/// A simple but honest adversary: it flies the same physics as you and steers with stick and throttle.
public struct BanditAI {
    public var skill: Double = 0.7   // 0...1
    public init(skill: Double = 0.7) { self.skill = skill }

    public func input(bandit: Aircraft, target: Aircraft) -> PilotInput {
        var input = PilotInput()
        let me = bandit.state
        let toTarget = target.state.position - me.position
        let distance = simd_length(toTarget)
        let leadTime = clamp(distance / 900, 0, 1.2) * skill
        var aim = target.state.position + target.state.velocity * leadTime - me.position

        // Terrain avoidance beats everything else.
        let ahead = me.position + me.velocity * 5
        let clearance = ahead.y - Terrain.height(x: ahead.x, z: ahead.z)
        let agl = me.position.y - Terrain.height(x: me.position.x, z: me.position.z)
        if clearance < 600 || agl < 500 {
            aim = Vec3(me.velocity.x, 0, me.velocity.z) + Vec3(0, simd_length(me.velocity) * 1.5, 0)
        }

        let d = simd_normalize(me.orientation.inverse.act(aim))
        // Roll so the target sits "above" us in the cockpit, then pull toward it.
        let bankError = atan2(d.x, d.y)
        let offNose = acos(clamp(-d.z, -1, 1))
        let rollGain = 1.5 * (0.5 + skill)
        input.roll = clamp(bankError * rollGain - me.rollRate * 0.15, -1, 1) * (offNose < 0.03 ? 0.2 : 1)
        let pull = clamp(atan2(d.y, -d.z) * 2.5, -0.3, 1)
        input.pitch = pull * (0.6 + 0.4 * skill)
        input.throttle = distance > 1200 ? 1.0 : 0.9
        input.trigger = offNose < 2.5.radians && distance < 900
        return input
    }
}

// MARK: - Session

public enum SessionEvent: Equatable {
    case stepCompleted(String)
    case lessonPassed
    case lessonFailed(String)
    case crashed(String)
    case touchdown(TouchdownReport)
    case gatePassed(Int)
    case gateMissed(Int)
    case hitBandit
    case gotHit
    case banditDestroyed
}

public enum SessionMode {
    case freeFlight(AircraftSpec.Kind, airborne: Bool)
    case lesson(Lesson)

    public var title: String {
        switch self {
        case .freeFlight(let kind, _): return "Free Flight — \(AircraftSpec.of(kind).name)"
        case .lesson(let l): return "Lesson \(l.number): \(l.title)"
        }
    }
}

/// One flight: the player's aircraft, optional bandit and gates, the lesson and the instructor.
/// Pure simulation, no UI; the app calls `advance(by:)` every frame.
public struct FlightSession {
    public static let physicsRate = 240.0

    public let mode: SessionMode
    public var player: Aircraft
    public var bandit: Aircraft?
    public var banditAI = BanditAI()
    public var gates: [Gate] = []
    public var wind = WindModel()
    public var input = PilotInput()
    public var time = 0.0
    public var lesson: LessonProgress?
    public var instructor = Instructor()
    public private(set) var hints: [Hint] = []
    public private(set) var telemetry = Telemetry()
    public private(set) var events: [SessionEvent] = []
    public private(set) var ammo = 600
    public private(set) var firing = false
    public private(set) var banditFiring = false
    public private(set) var trail: [Vec3] = []
    public private(set) var banditTrail: [Vec3] = []
    public var paused = false

    private var accumulator = 0.0
    private var wasCrashed = false
    private var lastTouchdownCount = 0
    private var trailTimer = 0.0

    public init(mode: SessionMode, autoRudder: Bool = true, wind: WindModel = WindModel()) {
        self.mode = mode
        self.wind = wind
        switch mode {
        case .freeFlight(let kind, let airborne):
            player = Aircraft(spec: .of(kind))
            if airborne {
                let spec = player.spec
                player.placeInFlight(position: Vec3(0, (kind == .trainer ? 3000 : 10000) * Units.foot, 3000),
                                     headingDeg: 0, airspeedKt: kind == .trainer ? spec.vCruiseKt * 0.9 : 380)
            } else {
                player.placeOnRunway()
            }
        case .lesson(let l):
            player = Aircraft(spec: .of(l.aircraft))
            switch l.start {
            case .runway:
                player.placeOnRunway()
            case let .air(x, altFt, z, heading, speed, flaps, gear):
                player.placeInFlight(position: Vec3(x, altFt * Units.foot, z), headingDeg: heading, airspeedKt: speed, gearDown: gear, flaps: flaps)
            }
            lesson = LessonProgress(lesson: l)
            if l.hasGates { gates = CanyonRoute.gates() }
            if l.hasBandit {
                var b = Aircraft(spec: .fighter)
                let p = player.state.position
                b.placeInFlight(position: p + Vec3(600, 150, -6000), headingDeg: 180, airspeedKt: 380, gearDown: false)
                bandit = b
            }
        }
        player.autoRudder = autoRudder
        input.throttle = player.state.engine
        telemetry = Telemetry(aircraft: player, input: input, time: 0)
    }

    public var outcome: LessonProgress.Status? { lesson?.status }
    public var banditDistance: Double? { bandit.map { simd_length($0.state.position - player.state.position) } }

    public mutating func drainEvents() -> [SessionEvent] {
        defer { events.removeAll() }
        return events
    }

    /// Runs as many fixed physics steps as fit in `frameTime`.
    public mutating func advance(by frameTime: Double) {
        guard !paused else { return }
        accumulator += min(frameTime, 0.1)
        let dt = 1 / Self.physicsRate
        var steps = 0
        while accumulator >= dt {
            step(dt: dt)
            accumulator -= dt
            steps += 1
        }
        let frameDt = Double(steps) * dt
        guard frameDt > 0 else { return }
        telemetry = Telemetry(aircraft: player, input: input, time: time)
        hints = instructor.evaluate(telemetry, spec: player.spec, dt: frameDt)
        updateLesson(dt: frameDt)
        recordTrails(dt: frameDt)
    }

    mutating func step(dt: Double) {
        time += dt
        let agl = player.state.position.y - Terrain.height(x: player.state.position.x, z: player.state.position.z)
        let w = wind.sample(dt: dt, altitudeAGL: agl)
        let before = player.state.position
        player.step(dt: dt, input: input, wind: w)

        if player.state.crashed && !wasCrashed {
            wasCrashed = true
            events.append(.crashed(player.state.crashReason ?? "Crashed"))
        }
        if player.touchdownCount != lastTouchdownCount, let report = player.lastTouchdown {
            lastTouchdownCount = player.touchdownCount
            events.append(.touchdown(report))
        }
        updateGates(from: before, to: player.state.position)
        updateCombat(dt: dt)
    }

    mutating func updateGates(from a: Vec3, to b: Vec3) {
        for i in gates.indices where gates[i].status == .pending {
            let g = gates[i]
            let da = simd_dot(a - g.center, g.normal)
            let db = simd_dot(b - g.center, g.normal)
            guard da < 0 && db >= 0 else { continue }
            let t = da / (da - db)
            let crossing = a + (b - a) * t
            if simd_length(crossing - g.center) <= g.radius {
                gates[i].status = .passed
                events.append(.gatePassed(i))
            } else {
                gates[i].status = .missed
                events.append(.gateMissed(i))
            }
        }
    }

    mutating func updateCombat(dt: Double) {
        guard var b = bandit else { return }
        firing = input.trigger && ammo > 0 && !player.state.crashed
        if firing {
            ammo = max(0, ammo - Int((100 * dt).rounded(.up)))
            if b.state.health > 0 && Self.onTarget(shooter: player.state, target: b.state, cone: 1.2.radians, range: 1200) {
                b.state.health -= 40 * dt
                if Int(time * 10) != Int((time - dt) * 10) { events.append(.hitBandit) }
                if b.state.health <= 0 {
                    b.state.health = 0
                    events.append(.banditDestroyed)
                }
            }
        }

        if b.state.health > 0 && !b.state.crashed {
            var aiInput = banditAI.input(bandit: b, target: player)
            if player.state.crashed { aiInput.trigger = false }
            banditFiring = aiInput.trigger
            b.step(dt: dt, input: aiInput, wind: wind.steady)
            if aiInput.trigger && Self.onTarget(shooter: b.state, target: player.state, cone: 2.radians, range: 900) {
                player.state.health -= 12 * dt * banditAI.skill
                if Int(time * 4) != Int((time - dt) * 4) { events.append(.gotHit) }
                if player.state.health <= 0 {
                    player.state.health = 0
                    player.state.crashed = true
                    player.state.crashReason = "Shot down by the bandit"
                }
            }
            if b.state.crashed && b.state.health > 0 {
                b.state.health = 0
                events.append(.banditDestroyed)
            }
        } else {
            banditFiring = false
            // A destroyed bandit falls out of the sky.
            b.state.velocity.y -= Units.g * dt
            b.state.position += b.state.velocity * dt
        }
        bandit = b
    }

    /// True when the target is inside the shooter's gun cone and in range.
    public static func onTarget(shooter: AircraftState, target: AircraftState, cone: Double, range: Double) -> Bool {
        let to = target.position - shooter.position
        let d = simd_length(to)
        guard d < range, d > 1 else { return false }
        let angle = acos(clamp(simd_dot(to / d, shooter.forward), -1, 1))
        return angle < cone + atan(6 / d)
    }

    mutating func updateLesson(dt: Double) {
        guard var progress = lesson, progress.status == .running else { return }
        let ctx = StepContext(start: telemetry, elapsed: 0,
                              gatesPassed: gates.filter { $0.status == .passed }.count,
                              gatesMissed: gates.filter { $0.status == .missed }.count,
                              gatesTotal: gates.count,
                              banditDistance: banditDistance,
                              banditDestroyed: bandit.map { $0.state.health <= 0 } ?? false,
                              lastTouchdown: player.lastTouchdown)
        let title = progress.currentStep?.title ?? ""
        if progress.update(telemetry, mission: ctx, dt: dt) {
            events.append(.stepCompleted(title))
        }
        switch progress.status {
        case .passed: events.append(.lessonPassed)
        case .failed(let reason): events.append(.lessonFailed(reason))
        case .running: break
        }
        lesson = progress
    }

    /// Context for the lesson panel's live progress text.
    public var stepContext: StepContext? {
        guard let progress = lesson else { return nil }
        return progress.context(telemetry, mission: StepContext(
            start: telemetry, elapsed: 0,
            gatesPassed: gates.filter { $0.status == .passed }.count,
            gatesMissed: gates.filter { $0.status == .missed }.count,
            gatesTotal: gates.count, banditDistance: banditDistance,
            banditDestroyed: bandit.map { $0.state.health <= 0 } ?? false,
            lastTouchdown: player.lastTouchdown))
    }

    mutating func recordTrails(dt: Double) {
        trailTimer += dt
        guard trailTimer >= 0.5 else { return }
        trailTimer = 0
        trail.append(player.state.position)
        if trail.count > 1200 { trail.removeFirst(trail.count - 1200) }
        if let b = bandit {
            banditTrail.append(b.state.position)
            if banditTrail.count > 240 { banditTrail.removeFirst() }
        }
    }

    // Convenience controls for the app
    public mutating func setFlaps(step: Int) { player.setFlaps(step: step) }
    public mutating func toggleGear() { player.toggleGear() }
    public mutating func adjustTrim(_ d: Double) { player.adjustTrim(d) }
}
