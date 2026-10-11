import SwiftUI
import AppKit
import FlightCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TopGunSimulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var sim = SimulationController()

    init() { SimSettings.registerDefaults() }

    var body: some Scene {
        WindowGroup("Top Gun Simulator") {
            ContentView()
                .environmentObject(sim)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Flight") {
                Button("Pause / Resume") { sim.handle(.togglePause) }.disabled(!sim.isFlying)
                Button("Restart") { sim.restart() }.disabled(!sim.isFlying)
                Button("Next Camera") { sim.handle(.nextCamera) }.disabled(!sim.isFlying)
                Divider()
                Button("End Flight") { sim.end() }.disabled(!sim.isFlying)
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Controls") { sim.showHelp = true }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(sim)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var sim: SimulationController
    @AppStorage(SettingsKey.showSidebar) private var showSidebar = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if sim.isFlying {
                FlightView()
            } else {
                HomeView()
            }
            FeedbackTab()
                .padding(.trailing, sim.isFlying && showSidebar ? 342 : 10)
                .padding(.bottom, sim.isFlying ? 196 : 10)
        }
        .sheet(isPresented: $sim.showHelp) { ControlsHelpView() }
        .navigationTitle(sim.title)
        .onAppear(perform: startFromLaunchArguments)
    }

    /// `--start <lesson-id | free-trainer | free-fighter | air-trainer | air-fighter>` opens straight into a flight
    /// (handy for demos and screenshots). `--camera <Chase|Cockpit|Orbit|Tower>` picks the view.
    private func startFromLaunchArguments() {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        if let cam = value("--camera").flatMap(CameraMode.init(rawValue:)) { sim.camera = cam }
        guard let start = value("--start"), !sim.isFlying else { return }
        switch start {
        case "free-trainer": sim.start(.freeFlight(.trainer, airborne: false))
        case "free-fighter": sim.start(.freeFlight(.fighter, airborne: false))
        case "air-trainer": sim.start(.freeFlight(.trainer, airborne: true))
        case "air-fighter": sim.start(.freeFlight(.fighter, airborne: true))
        default: if let l = LessonCatalog.lesson(id: start) { sim.start(.lesson(l)) }
        }
    }
}
