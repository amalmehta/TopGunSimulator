import Foundation
import simd

/// Lesson families. The app colours related categories in the same hue family.
public enum LessonCategory: String, CaseIterable, Identifiable {
    case basics = "Basics"
    case maneuvers = "Maneuvers"
    case takeoff = "Takeoff"
    case landing = "Landing"
    case canyon = "Low Level"
    case dogfight = "Dogfight"
    public var id: String { rawValue }

    public var group: String {
        switch self {
        case .basics, .maneuvers: return "Airwork"
        case .takeoff, .landing: return "Takeoff & Landing"
        case .canyon, .dogfight: return "Top Gun"
        }
    }
}

/// What a step's check can see: the live telemetry, the telemetry when the step began, and mission progress.
public struct StepContext {
    public var start: Telemetry
    public var elapsed: Double
    public var gatesPassed = 0
    public var gatesMissed = 0
    public var gatesTotal = 0
    public var banditDistance: Double?
    public var banditDestroyed = false
    public var lastTouchdown: TouchdownReport?
}

public struct LessonStep {
    public var title: String
    public var instruction: String
    public var tip: String
    /// The check must stay true this many seconds in a row.
    public var hold: Double
    public var check: (Telemetry, StepContext) -> Bool
    /// Returns a reason when the student has failed the step.
    public var fail: ((Telemetry, StepContext) -> String?)?
    /// Short live readout for the lesson panel, e.g. "Altitude 3,120 ft (target 3,500)".
    public var progress: ((Telemetry, StepContext) -> String)?

    public init(_ title: String, _ instruction: String, tip: String = "", hold: Double = 0,
                check: @escaping (Telemetry, StepContext) -> Bool,
                fail: ((Telemetry, StepContext) -> String?)? = nil,
                progress: ((Telemetry, StepContext) -> String)? = nil) {
        self.title = title; self.instruction = instruction; self.tip = tip; self.hold = hold
        self.check = check; self.fail = fail; self.progress = progress
    }
}

public enum LessonStart {
    case runway
    case air(x: Double, altitudeFt: Double, z: Double, headingDeg: Double, speedKt: Double, flaps: Double, gearDown: Bool?)
}

public struct Lesson: Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var category: LessonCategory
    public var aircraft: AircraftSpec.Kind
    public var summary: String
    public var objectives: [String]
    public var start: LessonStart
    public var hasGates = false
    public var hasBandit = false
    public var steps: [LessonStep]
}

/// Tracks a student's progress through one lesson.
public struct LessonProgress {
    public enum Status: Equatable { case running, passed, failed(String) }
    public let lesson: Lesson
    public private(set) var stepIndex = 0
    public private(set) var status = Status.running
    public private(set) var holdTime = 0.0
    private var stepStart = Telemetry()
    private var stepStartTime = 0.0
    private var started = false

    public init(lesson: Lesson) { self.lesson = lesson }

    public var currentStep: LessonStep? { stepIndex < lesson.steps.count ? lesson.steps[stepIndex] : nil }
    public var fractionComplete: Double { Double(stepIndex) / Double(max(lesson.steps.count, 1)) }

    public func context(_ t: Telemetry, mission: StepContext) -> StepContext {
        var c = mission
        c.start = stepStart
        c.elapsed = t.time - stepStartTime
        return c
    }

    /// Advances the lesson. Returns true when a step was just completed.
    @discardableResult
    public mutating func update(_ t: Telemetry, mission: StepContext, dt: Double) -> Bool {
        guard status == .running, let step = currentStep else { return false }
        if !started { started = true; stepStart = t; stepStartTime = t.time }
        if t.crashed { status = .failed(t.crashReason ?? "Crashed"); return false }
        let ctx = context(t, mission: mission)
        if let reason = step.fail?(t, ctx) { status = .failed(reason); return false }
        guard step.check(t, ctx) else { holdTime = 0; return false }
        holdTime += dt
        guard holdTime >= step.hold else { return false }
        stepIndex += 1
        holdTime = 0
        stepStart = t
        stepStartTime = t.time
        if stepIndex >= lesson.steps.count { status = .passed }
        return true
    }
}

// MARK: - Catalog

private func ft(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
private func within(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

public enum LessonCatalog {
    public static let all: [Lesson] = [
        controls, straightAndLevel, powerAndPitch, turns, climbsAndDescents, stalls,
        takeoff, landing, jetFamiliarization, canyonRun, dogfight,
    ]

    public static func lesson(id: String) -> Lesson? { all.first { $0.id == id } }

    static let cruise = LessonStart.air(x: 0, altitudeFt: 3000, z: 2000, headingDeg: 0, speedKt: 105, flaps: 0, gearDown: nil)

    static let controls = Lesson(
        id: "controls", number: 1, title: "The Controls", category: .basics, aircraft: .trainer,
        summary: "Meet the three axes: pitch, roll and yaw, and the throttle.",
        objectives: ["Pitch with the elevator", "Bank with the ailerons", "Yaw with the rudder", "Use the throttle"],
        start: cruise,
        steps: [
            LessonStep("Pitch up", "Pull back gently (S or ↓) until the nose is 10° above the horizon.",
                       tip: "The elevator on the tail pushes the tail down, which tips the nose up.", hold: 1,
                       check: { t, _ in t.pitchDeg > 8 }, progress: { t, _ in "Pitch \(Int(t.pitchDeg))° (target 10° up)" }),
            LessonStep("Pitch down", "Push forward (W or ↑) until the nose is below the horizon.",
                       tip: "Watch the airspeed rise as the nose drops. Pitch trades height for speed.", hold: 1,
                       check: { t, _ in t.pitchDeg < -3 }, progress: { t, _ in "Pitch \(Int(t.pitchDeg))° (target below 0°)" }),
            LessonStep("Level the nose", "Bring the nose back to the horizon and hold it there.",
                       hold: 2, check: { t, _ in abs(t.pitchDeg) < 3 }),
            LessonStep("Roll left", "Push the stick left (A or ←) to bank 30° left.",
                       tip: "The ailerons move in opposite directions: one wing gains lift, the other loses it.", hold: 1,
                       check: { t, _ in t.bankDeg < -25 }, progress: { t, _ in "Bank \(Int(t.bankDeg))°" }),
            LessonStep("Roll right", "Now roll the other way to 30° right (D or →).", hold: 1,
                       check: { t, _ in t.bankDeg > 25 }, progress: { t, _ in "Bank \(Int(t.bankDeg))°" }),
            LessonStep("Wings level", "Centre the stick and level the wings.", hold: 2,
                       check: { t, _ in abs(t.bankDeg) < 5 && abs(t.pitchDeg) < 6 }),
            LessonStep("Yaw", "Press the rudder (Q or E) and watch the nose slide sideways. Turn auto-rudder off in Settings to feel it fully.",
                       tip: "Rudder points the nose. It doesn't turn the plane by itself; banking does.", hold: 0.5,
                       check: { t, _ in abs(t.rudder) > 0.5 }),
            LessonStep("Power back", "Pull the throttle to idle (F). Notice the nose wants to drop.",
                       check: { t, _ in t.throttle < 0.1 }),
            LessonStep("Full power", "Push the throttle full forward (R).",
                       check: { t, _ in t.throttle > 0.95 }),
        ])

    static let straightAndLevel = Lesson(
        id: "straight-level", number: 2, title: "Straight and Level", category: .basics, aircraft: .trainer,
        summary: "Hold a constant altitude and heading, and use trim to fly hands-off.",
        objectives: ["Hold altitude ±100 ft", "Hold heading ±10°", "Trim off the control pressure"],
        start: .air(x: 0, altitudeFt: 3000, z: 2000, headingDeg: 0, speedKt: 95, flaps: 0, gearDown: nil),
        steps: [
            LessonStep("Hold it steady", "Keep altitude within 100 ft and heading within 10° of where you started, for 20 seconds.",
                       tip: "Pick a spot on the horizon and keep the nose on it. Small corrections, early.", hold: 20,
                       check: { t, c in within(t.altitudeFt, c.start.altitudeFt, 100) && abs(headingDelta(t.headingDeg, c.start.headingDeg)) < 10 },
                       fail: { t, c in abs(t.altitudeFt - c.start.altitudeFt) > 600 ? "Drifted more than 600 ft off altitude" : nil },
                       progress: { t, c in "Alt \(ft(t.altitudeFt)) ft (target \(ft(c.start.altitudeFt)))   Hdg \(Int(t.headingDeg))°" }),
            LessonStep("Trim for hands-off", "Let go of the stick, then use trim (, nose down / . nose up) until the vertical speed stays near zero for 6 seconds.",
                       tip: "Trim tells the aeroplane what attitude to hold. A trimmed plane flies itself.", hold: 6,
                       check: { t, _ in abs(t.stickPitch) < 0.05 && abs(t.verticalSpeedFpm) < 200 },
                       progress: { t, _ in "VS \(Int(t.verticalSpeedFpm)) fpm, trim \(String(format: "%+.2f", t.trim))" }),
        ])

    static let powerAndPitch = Lesson(
        id: "power-pitch", number: 3, title: "Power and Pitch", category: .basics, aircraft: .trainer,
        summary: "Change airspeed without changing altitude: power and pitch work together.",
        objectives: ["Slow down while holding altitude", "Speed up while holding altitude"],
        start: cruise,
        steps: [
            LessonStep("Slow to 75 kt", "Reduce power (F) and raise the nose gradually to hold altitude as you slow to 70–80 kt.",
                       tip: "Less speed means less lift, so you need more angle of attack (nose up) to stay level.", hold: 5,
                       check: { t, c in within(t.airspeedKt, 75, 5) && within(t.altitudeFt, c.start.altitudeFt, 150) },
                       progress: { t, c in "Speed \(Int(t.airspeedKt)) kt   Alt \(ft(t.altitudeFt - c.start.altitudeFt)) ft from start" }),
            LessonStep("Speed up to 110 kt", "Add power (R) and lower the nose to stay level as you accelerate to 105–115 kt.", hold: 5,
                       check: { t, c in within(t.airspeedKt, 110, 5) && within(t.altitudeFt, c.start.altitudeFt, 150) },
                       progress: { t, c in "Speed \(Int(t.airspeedKt)) kt   Alt \(ft(t.altitudeFt - c.start.altitudeFt)) ft from start" }),
        ])

    static let turns = Lesson(
        id: "turns", number: 4, title: "Turns", category: .maneuvers, aircraft: .trainer,
        summary: "Bank to turn, add back pressure to hold altitude, roll out on a heading.",
        objectives: ["30° banked turns", "Hold altitude in the turn", "Roll out on a target heading"],
        start: cruise,
        steps: [
            LessonStep("Bank left 30°", "Roll into a 30° left bank and hold it.",
                       tip: "Banking tilts the lift sideways. That sideways pull is what turns you.", hold: 3,
                       check: { t, _ in within(t.bankDeg, -30, 7) }, progress: { t, _ in "Bank \(Int(t.bankDeg))°" }),
            LessonStep("Turn to 270°", "Keep the bank, add a little back pressure to hold altitude, and roll wings level on heading 270° (west).",
                       tip: "Start rolling out about 10° before the target heading.", hold: 2,
                       check: { t, _ in abs(headingDelta(t.headingDeg, 270)) < 10 && abs(t.bankDeg) < 6 },
                       fail: { t, c in abs(t.altitudeFt - c.start.altitudeFt) > 500 ? "Lost or gained more than 500 ft in the turn" : nil },
                       progress: { t, c in "Hdg \(Int(t.headingDeg))° → 270°   Alt Δ \(ft(t.altitudeFt - c.start.altitudeFt)) ft" }),
            LessonStep("Turn right to 360°", "Now a 30° right turn back to north (360°), rolling out wings level.", hold: 2,
                       check: { t, _ in abs(headingDelta(t.headingDeg, 0)) < 10 && abs(t.bankDeg) < 6 },
                       fail: { t, c in abs(t.altitudeFt - c.start.altitudeFt) > 500 ? "Lost or gained more than 500 ft in the turn" : nil },
                       progress: { t, _ in "Hdg \(Int(t.headingDeg))° → 360°   Bank \(Int(t.bankDeg))°" }),
        ])

    static let climbsAndDescents = Lesson(
        id: "climbs-descents", number: 5, title: "Climbs and Descents", category: .maneuvers, aircraft: .trainer,
        summary: "Climb and descend at a set speed, and level off on a target altitude.",
        objectives: ["Climb 500 ft at 75 kt", "Level off", "Descend at about 500 fpm"],
        start: cruise,
        steps: [
            LessonStep("Climb 500 ft", "Full power (R) and raise the nose to hold about 75 kt. Climb to 3,500 ft.",
                       tip: "In a climb, pitch sets your airspeed and power sets your climb rate.",
                       check: { t, _ in t.altitudeFt >= 3480 },
                       progress: { t, _ in "Alt \(ft(t.altitudeFt)) / 3,500 ft   Speed \(Int(t.airspeedKt)) kt" }),
            LessonStep("Level off at 3,500", "Lower the nose to the horizon, let speed build, then reduce power. Hold 3,500 ft.",
                       tip: "Attitude, then power, then trim: APT.", hold: 5,
                       check: { t, _ in within(t.altitudeFt, 3500, 100) && abs(t.verticalSpeedFpm) < 250 },
                       progress: { t, _ in "Alt \(ft(t.altitudeFt)) ft   VS \(Int(t.verticalSpeedFpm)) fpm" }),
            LessonStep("Descend to 3,000", "Reduce power a little and lower the nose for about 500 fpm down. Level at 3,000 ft.", hold: 4,
                       check: { t, _ in within(t.altitudeFt, 3000, 100) && abs(t.verticalSpeedFpm) < 250 },
                       progress: { t, _ in "Alt \(ft(t.altitudeFt)) → 3,000 ft   VS \(Int(t.verticalSpeedFpm)) fpm" }),
        ])

    static let stalls = Lesson(
        id: "stalls", number: 6, title: "Slow Flight and Stalls", category: .maneuvers, aircraft: .trainer,
        summary: "Feel the stall coming, let it happen, and recover the right way.",
        objectives: ["Recognise the stall warning", "Stall the wing", "Recover: nose down, full power, wings level"],
        start: .air(x: 0, altitudeFt: 4500, z: 2000, headingDeg: 0, speedKt: 95, flaps: 0, gearDown: nil),
        steps: [
            LessonStep("Power to idle", "Pull the throttle to idle (F) and keep the nose level as you slow down.",
                       check: { t, _ in t.throttle < 0.15 }),
            LessonStep("Stall it", "Keep raising the nose to hold altitude until the wing stalls. Watch the AoA climb.",
                       tip: "The stall happens at a critical angle of attack (~15° here), not a particular speed.",
                       check: { t, _ in t.stalled },
                       progress: { t, _ in "AoA \(Int(t.alphaDeg))° (stalls ≈ 15°)   Speed \(Int(t.airspeedKt)) kt" }),
            LessonStep("Recover", "Stick FORWARD to un-stall the wing, full power (R), wings level with ailerons and rudder.",
                       tip: "Every stall recovery starts with reducing angle of attack.", hold: 2,
                       check: { t, _ in !t.stalled && t.throttle > 0.9 && t.alphaDeg < 10 },
                       fail: { t, _ in t.aglFt < 800 ? "Too low: recover with more altitude next time" : nil }),
            LessonStep("Climb away", "Once flying again, gently pull out of the dive and climb at 70+ kt.", hold: 3,
                       check: { t, _ in t.verticalSpeedFpm > 0 && t.airspeedKt > 65 && !t.stalled },
                       fail: { t, _ in t.aglFt < 500 ? "Too low: recover with more altitude next time" : nil }),
        ])

    static let takeoff = Lesson(
        id: "takeoff", number: 7, title: "Takeoff", category: .takeoff, aircraft: .trainer,
        summary: "Full power, keep it straight, rotate and climb out.",
        objectives: ["Track the centreline with rudder", "Rotate at 55 kt", "Climb at 75 kt to 500 ft"],
        start: .runway,
        steps: [
            LessonStep("Full power", "Release the brakes and push the throttle to full (hold R).",
                       check: { t, _ in t.throttle > 0.95 }),
            LessonStep("Keep it straight", "The propeller pulls you left: use rudder (E / Q) to stay on the centreline as you accelerate. Auto-rudder helps; switch it off in Settings to feel it.",
                       tip: "Look far down the runway, not at the nose.",
                       check: { t, _ in t.airspeedKt > 45 },
                       fail: { t, _ in t.onGround && !t.onRunway && t.groundSpeedKt > 5 ? "Ran off the runway" : nil },
                       progress: { t, _ in "Speed \(Int(t.airspeedKt)) kt   Centreline \(String(format: "%+.0f", t.position.x)) m" }),
            LessonStep("Rotate", "At 55 kt ease back (S / ↓) to raise the nose about 8° and fly off.",
                       check: { t, _ in !t.onGround && t.aglFt > 20 },
                       fail: { t, _ in t.onGround && !t.onRunway && t.groundSpeedKt > 5 ? "Ran off the runway" : nil }),
            LessonStep("Climb out", "Climb at about 75 kt to 500 ft above the ground.",
                       tip: "Hold the nose about 8–10° up and watch the airspeed.",
                       check: { t, _ in t.aglFt > 500 },
                       progress: { t, _ in "AGL \(ft(t.aglFt)) / 500 ft   Speed \(Int(t.airspeedKt)) kt" }),
        ])

    static let landing = Lesson(
        id: "landing", number: 8, title: "Landing", category: .landing, aircraft: .trainer,
        summary: "Fly a stabilised approach from 2 miles out, flare, touch down and stop.",
        objectives: ["Configure flaps", "Hold 65 kt on a ~3° glidepath", "Flare and touch down gently", "Stop on the runway"],
        start: .air(x: 0, altitudeFt: 650, z: Terrain.runwaySouthEnd + 3700, headingDeg: 0, speedKt: 75, flaps: 1.0 / 3, gearDown: nil),
        steps: [
            LessonStep("Configure", "Set full flaps (] twice more) and slow to 60–70 kt.",
                       tip: "Flaps add lift and drag, so you can fly slower and descend steeper.", hold: 2,
                       check: { t, _ in t.flapsDeg >= 25 && within(t.airspeedKt, 65, 6) },
                       progress: { t, _ in "Flaps \(Int(t.flapsDeg))°   Speed \(Int(t.airspeedKt)) kt" }),
            LessonStep("Fly the glidepath", "Aim at the runway numbers. Keep about 65 kt and 400–500 fpm down. Power controls the descent.",
                       tip: "If the numbers move up the windshield you're going to land short: add power.",
                       check: { t, _ in t.aglFt < 30 && !t.onGround },
                       progress: { t, _ in
                           let dist = max(t.position.z - Terrain.runwaySouthEnd, 1)
                           let ideal = dist * tan(3.radians) / Units.foot
                           return "AGL \(ft(t.aglFt)) ft (glidepath \(ft(ideal)))   Speed \(Int(t.airspeedKt)) kt" }),
            LessonStep("Flare", "Power to idle and gently raise the nose to slow the descent just above the runway.",
                       tip: "Hold it off. Let the plane settle onto the main wheels.",
                       check: { t, _ in t.onGround },
                       fail: { t, c in t.onGround && !t.onRunway ? "Touched down off the runway" : nil }),
            LessonStep("Stop", "Hold the brakes (B) and keep straight with rudder until stopped.",
                       check: { t, _ in t.groundSpeedKt < 3 && t.onGround },
                       fail: { t, _ in t.onGround && !t.onRunway && t.groundSpeedKt > 5 ? "Ran off the runway" : nil }),
        ])

    static let jetFamiliarization = Lesson(
        id: "jet-fam", number: 9, title: "Jet Familiarization", category: .dogfight, aircraft: .fighter,
        summary: "Get a feel for the fighter: afterburner, high-g turns and the vertical.",
        objectives: ["Light the afterburner", "Sustain a 5 g turn", "Go vertical", "Recover to level flight"],
        start: .air(x: 0, altitudeFt: 12000, z: 0, headingDeg: 0, speedKt: 380, flaps: 0, gearDown: false),
        steps: [
            LessonStep("Afterburner", "Push the throttle all the way (hold R) to light the burners.",
                       check: { t, _ in t.afterburner }),
            LessonStep("Pull 5 g", "Bank 70–80° and pull hard to hold 5 g or more for 3 seconds.",
                       tip: "The fly-by-wire system limits you to 7.5 g. Feel how fast the speed bleeds.", hold: 3,
                       check: { t, _ in t.gLoad > 5 }, progress: { t, _ in String(format: "%.1f g", t.gLoad) }),
            LessonStep("Go vertical", "Roll wings level and pull to 60° nose-up or more.",
                       check: { t, _ in t.pitchDeg > 60 }, progress: { t, _ in "Pitch \(Int(t.pitchDeg))°" }),
            LessonStep("Recover", "Roll and pull back to level flight: pitch within 5°, wings within 10°.", hold: 3,
                       check: { t, _ in abs(t.pitchDeg) < 5 && abs(t.bankDeg) < 10 },
                       fail: { t, _ in t.aglFt < 1500 ? "Too low" : nil }),
        ])

    static let canyonRun = Lesson(
        id: "canyon-run", number: 10, title: "Canyon Run", category: .canyon, aircraft: .fighter,
        summary: "Thread the gates down a winding canyon, low and fast.",
        objectives: ["Fly every gate", "Stay below the canyon rim", "Don't hit the walls"],
        start: CanyonRoute.start,
        hasGates: true,
        steps: [
            LessonStep("Fly the gates", "Fly through every orange ring. Use the map to see the next turn coming.",
                       tip: "Look through the turn. Bank first, then pull.",
                       check: { _, c in c.gatesPassed + c.gatesMissed >= c.gatesTotal && c.gatesTotal > 0 },
                       progress: { _, c in "Gates \(c.gatesPassed)/\(c.gatesTotal)" + (c.gatesMissed > 0 ? "   missed \(c.gatesMissed)" : "") }),
        ])

    static let dogfight = Lesson(
        id: "dogfight", number: 11, title: "Dogfight", category: .dogfight, aircraft: .fighter,
        summary: "One bandit, guns only. Get behind it and shoot it down.",
        objectives: ["Find the bandit", "Turn to get behind it", "Guns kill (Space)"],
        start: .air(x: 0, altitudeFt: 12000, z: 0, headingDeg: 0, speedKt: 380, flaps: 0, gearDown: false),
        hasBandit: true,
        steps: [
            LessonStep("Merge", "The bandit is ahead (red box on the HUD). Fly toward it.",
                       tip: "Watch the arrow at the edge of the HUD when it's off-screen.",
                       check: { _, c in (c.banditDistance ?? 1e9) < 2000 },
                       progress: { _, c in String(format: "Range %.1f nm", (c.banditDistance ?? 0) / 1852) }),
            LessonStep("Guns kill", "Turn behind it, put the pipper on it and hold Space to fire.",
                       tip: "Turn into the bandit to cut across its circle; then match its turn.",
                       check: { _, c in c.banditDestroyed },
                       fail: { t, _ in t.health <= 0 ? "You were shot down" : nil },
                       progress: { _, c in "Range \(Int(c.banditDistance ?? 0)) m" }),
        ])
}
