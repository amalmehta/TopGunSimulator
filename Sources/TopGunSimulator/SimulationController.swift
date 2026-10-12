import SwiftUI
import SceneKit
import FlightCore

/// What the SwiftUI layer shows, refreshed ~30 times a second.
struct FrameSnapshot {
    var telemetry = Telemetry()
    var hints: [Hint] = []
    var lessonStatus: LessonProgress.Status?
    var lessonStepIndex = 0
    var lessonProgressText: String?
    var lessonHold = 0.0
    var gates: [Gate] = []
    var trail: [Vec3] = []
    var banditTrail: [Vec3] = []
    var banditPosition: Vec3?
    var banditHeading = 0.0
    var banditHealth = 0.0
    var banditDistance: Double?
    var banditScreen: CGPoint?
    var nextGateScreen: CGPoint?
    var ammo = 0
    var touchdown: TouchdownReport?
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var color: Color
}

@MainActor
final class SimulationController: ObservableObject {
    @Published private(set) var frame = FrameSnapshot()
    @Published private(set) var isFlying = false
    @Published var camera: CameraMode = .chase
    @Published var paused = false
    @Published var showHelp = false
    @Published private(set) var toasts: [Toast] = []
    @Published private(set) var result: LessonProgress.Status?
    @Published private(set) var crashed: String?

    private(set) var session: FlightSession?
    private(set) var mode: SessionMode?
    let world = WorldScene()
    let input = InputManager()
    weak var sceneView: SCNView?
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var publishTimer = 0.0
    private(set) var settings = SimSettings.current

    var title: String { mode?.title ?? "Top Gun Simulator" }
    var lesson: Lesson? { if case .lesson(let l) = mode { return l }; return nil }
    var spec: AircraftSpec { session?.player.spec ?? .trainer }

    init() {
        input.onAction = { [weak self] action in
            MainActor.assumeIsolated { self?.handle(action) }
        }
    }

    // MARK: Lifecycle

    func start(_ mode: SessionMode) {
        settings = SimSettings.current
        var s = FlightSession(mode: mode, autoRudder: settings.autoRudder, wind: settings.wind)
        s.banditAI.skill = settings.banditSkill
        session = s
        self.mode = mode
        input.throttle = s.input.throttle
        input.onScreen = OnScreenControls()
        input.onScreen.active = settings.onScreenControls
        world.load(session: s)
        result = nil
        crashed = nil
        paused = false
        toasts = []
        camera = (lesson?.hasGates == true) ? .chase : camera
        isFlying = true
        input.start()
        lastTick = CACurrentMediaTime()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        publish()
    }

    func restart() { if let mode { start(mode) } }

    func end() {
        timer?.invalidate()
        timer = nil
        input.stop()
        session = nil
        isFlying = false
        result = nil
        crashed = nil
    }

    func startNextLesson() {
        guard let l = lesson, let i = LessonCatalog.all.firstIndex(where: { $0.id == l.id }), i + 1 < LessonCatalog.all.count else { end(); return }
        start(.lesson(LessonCatalog.all[i + 1]))
    }

    func refreshSettings() {
        settings = SimSettings.current
        session?.player.autoRudder = settings.autoRudder
        session?.wind = settings.wind
        session?.banditAI.skill = settings.banditSkill
        if input.onScreen.active != settings.onScreenControls {
            input.onScreen = OnScreenControls()
            input.onScreen.active = settings.onScreenControls
        }
    }

    // MARK: Frame loop

    private func tick() {
        guard var s = session else { return }
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        s.paused = paused || result != nil
        if !s.paused {
            s.input = input.sample(dt: dt, settings: settings)
            s.advance(by: dt)
        }
        for event in s.drainEvents() { handle(event) }
        session = s
        world.update(session: s, camera: camera, fov: settings.fieldOfView, dt: dt)

        publishTimer += dt
        if publishTimer >= 1.0 / 30 {
            publishTimer = 0
            publish()
        }
    }

    private func publish() {
        guard let s = session else { return }
        var f = FrameSnapshot()
        f.telemetry = s.telemetry
        f.hints = settings.instructorLevel == .off ? [] : s.hints
        f.lessonStatus = s.lesson?.status
        f.lessonStepIndex = s.lesson?.stepIndex ?? 0
        f.lessonHold = s.lesson?.holdTime ?? 0
        if let step = s.lesson?.currentStep, let ctx = s.stepContext { f.lessonProgressText = step.progress?(s.telemetry, ctx) }
        f.gates = s.gates
        f.trail = s.trail
        f.banditTrail = s.banditTrail
        f.ammo = s.ammo
        f.touchdown = s.player.lastTouchdown
        if let b = s.bandit {
            f.banditPosition = b.state.position
            f.banditHeading = b.state.headingDeg
            f.banditHealth = b.state.health
            f.banditDistance = s.banditDistance
        }
        if let view = sceneView {
            if let b = s.bandit, b.state.health > 0 { f.banditScreen = world.project(b.state.position, in: view) }
            if let g = s.gates.first(where: { $0.status == .pending }) { f.nextGateScreen = world.project(g.center, in: view) }
        }
        frame = f
    }

    // MARK: Events

    private func handle(_ event: SessionEvent) {
        switch event {
        case .stepCompleted(let title): toast("✓ \(title)", .green)
        case .lessonPassed:
            if let l = lesson { LessonRecord.markCompleted(l.id) }
            result = .passed
        case .lessonFailed(let reason): result = .failed(reason)
        case .crashed(let reason):
            crashed = reason
        case .touchdown(let r):
            let text = String(format: "Touchdown: %@ (%.0f fpm, %.0f m from centreline)", r.grade.rawValue, r.sinkRateFpm, abs(r.centerlineOffset))
            toast(text, r.grade == .hard ? .orange : .green)
        case .gatePassed(let i): toast("Gate \(i + 1) ✓", .green)
        case .gateMissed(let i): toast("Missed gate \(i + 1)", .orange)
        case .hitBandit: toast("Hit!", .yellow)
        case .gotHit: toast("You're taking hits: break turn!", .red)
        case .banditDestroyed: toast("Splash one! Bandit destroyed", .green)
        }
    }

    func toast(_ text: String, _ color: Color) {
        let t = Toast(text: text, color: color)
        toasts.append(t)
        if toasts.count > 4 { toasts.removeFirst() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.toasts.removeAll { $0.id == t.id }
        }
    }

    func handle(_ action: FlightAction) {
        if action == .toggleOnScreenControls {   // works from the home screen too
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: SettingsKey.onScreenControls), forKey: SettingsKey.onScreenControls)
            return
        }
        guard session != nil else { return }
        switch action {
        case .flapsDown: session?.setFlaps(step: 1); announceFlaps()
        case .flapsUp: session?.setFlaps(step: -1); announceFlaps()
        case .toggleGear:
            guard spec.hasRetractableGear else { toast("The trainer's gear is fixed", .secondary); return }
            session?.toggleGear()
            toast(session?.player.state.gearDown == true ? "Gear down" : "Gear up", .secondary)
        case .trimUp: session?.adjustTrim(0.02)
        case .trimDown: session?.adjustTrim(-0.02)
        case .nextCamera: camera = camera.next
        case .togglePause: paused.toggle()
        case .toggleHelp: showHelp.toggle()
        case .toggleSidebar: UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: SettingsKey.showSidebar), forKey: SettingsKey.showSidebar)
        case .toggleInstruments: UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: SettingsKey.showInstruments), forKey: SettingsKey.showInstruments)
        case .toggleOnScreenControls: break
        case .endFlight: end()
        case .restart: restart()
        }
    }

    private func announceFlaps() {
        guard let s = session else { return }
        let detents = s.player.spec.flapDetents
        let deg = s.player.state.flapsTarget * (detents.last ?? 0)
        toast("Flaps \(Int(deg.rounded()))°", .secondary)
    }

    // MARK: Orbit camera mouse control

    func orbit(dx: CGFloat, dy: CGFloat) {
        if camera != .orbit { camera = .orbit }
        world.orbitAzimuth -= Float(dx) * 0.01
        world.orbitElevation = Float(clamp(Double(world.orbitElevation) + Double(dy) * 0.01, -0.3, 1.4))
    }

    func zoom(_ delta: CGFloat) {
        world.orbitDistanceScale = Float(clamp(Double(world.orbitDistanceScale) * (1 - Double(delta) * 0.03), 0.5, 12))
    }
}
