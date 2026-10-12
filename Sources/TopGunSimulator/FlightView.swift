import SwiftUI
import SceneKit
import FlightCore

/// SCNView that lets the mouse orbit the camera and the scroll wheel zoom.
final class FlightSCNView: SCNView {
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    override func mouseDragged(with event: NSEvent) { onDrag?(event.deltaX, event.deltaY) }
    override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
    override var acceptsFirstResponder: Bool { false }
}

struct SceneViewRepresentable: NSViewRepresentable {
    let sim: SimulationController

    func makeNSView(context: Context) -> FlightSCNView {
        let v = FlightSCNView(frame: .zero)
        v.scene = sim.world.scene
        v.pointOfView = sim.world.cameraNode
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = .black
        v.onDrag = { dx, dy in MainActor.assumeIsolated { sim.orbit(dx: dx, dy: dy) } }
        v.onScroll = { d in MainActor.assumeIsolated { sim.zoom(d) } }
        sim.sceneView = v
        return v
    }

    func updateNSView(_ nsView: FlightSCNView, context: Context) {}
}

struct FlightView: View {
    @EnvironmentObject var sim: SimulationController
    @AppStorage(SettingsKey.showHUD) private var showHUD = true
    @AppStorage(SettingsKey.showInstruments) private var showInstruments = true
    @AppStorage(SettingsKey.showSidebar) private var showSidebar = true
    @AppStorage(SettingsKey.onScreenControls) private var onScreenControls = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    SceneViewRepresentable(sim: sim)
                    if showHUD {
                        HUDView(frame: sim.frame, spec: sim.spec, camera: sim.camera, fov: sim.settings.fieldOfView,
                                bottomInset: onScreenControls ? OnScreenControlsView.inset : 0)
                            .allowsHitTesting(false)
                    }
                    if onScreenControls {
                        OnScreenControlsView(telemetry: sim.frame.telemetry, spec: sim.spec)
                    }
                    ToastStack(toasts: sim.toasts)
                    overlays
                }
                if showInstruments {
                    InstrumentPanel(t: sim.frame.telemetry, spec: sim.spec)
                        .frame(height: 186)
                }
            }
            if showSidebar {
                Divider()
                SidebarView()
                    .frame(width: 330)
            }
        }
        .toolbar { toolbar }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            sim.refreshSettings()
        }
    }

    @ViewBuilder private var overlays: some View {
        if let reason = sim.crashed, sim.result == nil {
            ResultOverlay(title: "Crashed", message: reason, color: .red, passed: false)
        } else if let result = sim.result {
            switch result {
            case .passed:
                ResultOverlay(title: "Lesson passed", message: passedMessage, color: .green, passed: true)
            case .failed(let reason):
                ResultOverlay(title: "Lesson failed", message: reason, color: .orange, passed: false)
            case .running: EmptyView()
            }
        } else if sim.paused {
            ResultOverlay(title: "Paused", message: "Press P to resume.", color: .secondary, passed: false, isPause: true)
        }
    }

    private var passedMessage: String {
        var text = sim.lesson?.objectives.map { "✓ \($0)" }.joined(separator: "\n") ?? ""
        if let td = sim.frame.touchdown, sim.lesson?.category == .landing {
            text += String(format: "\n\nTouchdown: %@, %.0f fpm, %.0f m past the threshold, %.0f m off centreline",
                           td.grade.rawValue, td.sinkRateFpm, td.distanceFromThreshold, abs(td.centerlineOffset))
        }
        return text
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { sim.end() } label: { Label("Menu", systemImage: "chevron.backward") }
                .help("End flight and return to the menu (Esc)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Camera", selection: $sim.camera) {
                ForEach(CameraMode.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Camera (C). Drag in the view to orbit, scroll to zoom.")
            Button { sim.handle(.togglePause) } label: { Label(sim.paused ? "Resume" : "Pause", systemImage: sim.paused ? "play.fill" : "pause.fill") }
                .help("Pause (P)")
            Button { sim.restart() } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
                .help("Restart (\\)")
            Toggle(isOn: $showInstruments) { Label("Instruments", systemImage: "gauge.with.dots.needle.33percent") }
                .help("Instrument panel (I)")
            Toggle(isOn: $showSidebar) { Label("Map & Lesson", systemImage: "sidebar.right") }
                .help("Map, profile and lesson sidebar (M)")
            Toggle(isOn: $onScreenControls) { Label("On-screen Controls", systemImage: "hand.point.up.left") }
                .help("On-screen stick, rudder, throttle and buttons for mouse or trackpad (K)")
            Button { sim.showHelp = true } label: { Label("Controls", systemImage: "keyboard") }
                .help("Keyboard controls (H)")
            SettingsLink { Label("Settings", systemImage: "gearshape") }
                .help("Settings (⌘,)")
        }
    }
}

struct ToastStack: View {
    let toasts: [Toast]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(toasts) { t in
                Text(t.text)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.65)))
                    .overlay(Capsule().strokeBorder(t.color.opacity(0.8), lineWidth: 1.5))
                    .foregroundStyle(.white)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 60)
        .animation(.easeOut(duration: 0.25), value: toasts)
        .allowsHitTesting(false)
    }
}

struct ResultOverlay: View {
    @EnvironmentObject var sim: SimulationController
    let title: String
    let message: String
    let color: Color
    let passed: Bool
    var isPause = false

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(color)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.white).frame(maxWidth: 460)
            HStack {
                if isPause {
                    Button("Resume") { sim.paused = false }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Try again") { sim.restart() }.keyboardShortcut(passed ? .cancelAction : .defaultAction)
                }
                if passed && sim.lesson != nil {
                    Button("Next lesson") { sim.startNextLesson() }.keyboardShortcut(.defaultAction)
                }
                Button("Menu") { sim.end() }
            }
            .controlSize(.large)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.72)))
    }
}
