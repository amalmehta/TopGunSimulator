import SwiftUI
import FlightCore

/// Every preference in one place (⌘, or the gear button).
struct SettingsView: View {
    var body: some View {
        TabView {
            FlyingSettings().tabItem { Label("Flying", systemImage: "airplane") }
            InstructorSettings().tabItem { Label("Instructor", systemImage: "person.wave.2") }
            DisplaySettings().tabItem { Label("Display", systemImage: "display") }
            WorldSettings().tabItem { Label("World", systemImage: "wind") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct FlyingSettings: View {
    @AppStorage(SettingsKey.autoRudder) private var autoRudder = true
    @AppStorage(SettingsKey.invertPitch) private var invertPitch = false
    @AppStorage(SettingsKey.stickSensitivity) private var sensitivity = 1.0
    @AppStorage(SettingsKey.keyboardCentering) private var centering = 1.0
    @AppStorage(SettingsKey.onScreenControls) private var onScreenControls = false
    @AppStorage(SettingsKey.controllerTilt) private var controllerTilt = false
    @AppStorage(SettingsKey.tiltRangeDeg) private var tiltRange = 30.0
    @AppStorage(SettingsKey.tiltInvertPitch) private var tiltInvertPitch = false
    @State private var controllerStatus = InputManager.motionControllerStatus()

    var body: some View {
        Form {
            Toggle("Auto-rudder (keeps turns coordinated and the takeoff roll straight)", isOn: $autoRudder)
            Toggle("Invert pitch (W / ↑ pulls the nose up)", isOn: $invertPitch)
            LabeledContent("Stick sensitivity") {
                Slider(value: $sensitivity, in: 0.4...1.5) { EmptyView() } minimumValueLabel: { Text("Gentle") } maximumValueLabel: { Text("Sharp") }
            }
            LabeledContent("Keyboard re-centering") {
                Slider(value: $centering, in: 0.3...2.0) { EmptyView() } minimumValueLabel: { Text("Slow") } maximumValueLabel: { Text("Snappy") }
            }
            Toggle("On-screen controls (fly with the mouse or trackpad: stick, rudder, throttle and buttons)", isOn: $onScreenControls)
            Toggle("Tilt the game controller to fly (DualSense, DualShock 4 and other controllers with motion)", isOn: $controllerTilt)
            if controllerTilt {
                LabeledContent("Tilt for full stick") {
                    HStack { Slider(value: $tiltRange, in: 10...60, step: 5); Text("\(Int(tiltRange))°").monospacedDigit().frame(width: 36) }
                }
                Toggle("Invert tilt pitch", isOn: $tiltInvertPitch)
                Text("Hold the controller how you like and press L (or click the left stick) to make that straight and level. Moving the controller's stick overrides tilt.\n\(controllerStatus)")
                    .font(.callout).foregroundStyle(.secondary)
                    .onAppear { controllerStatus = InputManager.motionControllerStatus() }
            }
            Text("A game controller works too: left stick flies, right stick is rudder, triggers set the throttle, A fires.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct InstructorSettings: View {
    @AppStorage(SettingsKey.instructorLevel) private var level = InstructorLevel.explain.rawValue
    @State private var confirmReset = false

    var body: some View {
        Form {
            Picker("Instructor", selection: $level) {
                ForEach(InstructorLevel.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.radioGroup)
            Text("“Hints + why” explains the aerodynamics behind each tip. Warnings (stall, sink rate) always flash on the HUD unless the instructor is off.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Reset lesson progress…") { confirmReset = true }
                .confirmationDialog("Clear all passed lessons?", isPresented: $confirmReset) {
                    Button("Reset progress", role: .destructive) { LessonRecord.reset() }
                }
        }
        .padding()
    }
}

private struct DisplaySettings: View {
    @AppStorage(SettingsKey.showHUD) private var showHUD = true
    @AppStorage(SettingsKey.showInstruments) private var showInstruments = true
    @AppStorage(SettingsKey.showSidebar) private var showSidebar = true
    @AppStorage(SettingsKey.metricUnits) private var metric = false
    @AppStorage(SettingsKey.fieldOfView) private var fov = 65.0

    var body: some View {
        Form {
            Toggle("Head-up display", isOn: $showHUD)
            Toggle("Instrument panel (I)", isOn: $showInstruments)
            Toggle("Map, profile and lesson sidebar (M)", isOn: $showSidebar)
            Picker("Units", selection: $metric) {
                Text("Aviation (kt, ft, fpm)").tag(false)
                Text("Metric (km/h, m, m/s)").tag(true)
            }
            LabeledContent("Field of view") {
                HStack {
                    Slider(value: $fov, in: 40...95)
                    Text("\(Int(fov))°").monospacedDigit().frame(width: 36)
                }
            }
        }
        .padding()
    }
}

private struct WorldSettings: View {
    @AppStorage(SettingsKey.windSpeedKt) private var windSpeed = 0.0
    @AppStorage(SettingsKey.windFromDeg) private var windFrom = 360.0
    @AppStorage(SettingsKey.turbulence) private var turbulence = 0.0
    @AppStorage(SettingsKey.banditSkill) private var skill = 0.6

    var body: some View {
        Form {
            LabeledContent("Wind speed") {
                HStack { Slider(value: $windSpeed, in: 0...30, step: 1); Text("\(Int(windSpeed)) kt").monospacedDigit().frame(width: 44) }
            }
            LabeledContent("Wind from") {
                HStack { Slider(value: $windFrom, in: 0...360, step: 10); Text("\(Int(windFrom))°").monospacedDigit().frame(width: 44) }
            }
            LabeledContent("Turbulence") {
                Slider(value: $turbulence, in: 0...1) { EmptyView() } minimumValueLabel: { Text("Calm") } maximumValueLabel: { Text("Rough") }
            }
            LabeledContent("Bandit skill") {
                Slider(value: $skill, in: 0.2...1) { EmptyView() } minimumValueLabel: { Text("Rookie") } maximumValueLabel: { Text("Ace") }
            }
            Text("A crosswind (wind not from 360°) makes landings harder: point into the wind and use rudder to line up at touchdown.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ControlsHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let rows: [(String, String)] = [
        ("S / ↓", "Stick back: nose up"),
        ("W / ↑", "Stick forward: nose down"),
        ("A D / ← →", "Roll left / right (ailerons)"),
        ("Q / E", "Rudder left / right (yaw)"),
        ("R / F", "Throttle up / down (hold)"),
        ("[ / ]", "Flaps up / down"),
        (", / .", "Trim nose down / nose up"),
        ("G", "Gear up / down (fighter)"),
        ("B", "Wheel brakes (hold)"),
        ("Space", "Guns (fighter)"),
        ("C", "Next camera; drag the view to orbit, scroll to zoom"),
        ("P", "Pause"),
        ("I / M", "Toggle instruments / map sidebar"),
        ("K", "Toggle on-screen controls (mouse / trackpad)"),
        ("L", "Level controller tilt (or click the left stick)"),
        ("\\", "Restart"),
        ("Esc", "End flight"),
        ("H", "This help"),
        ("⌘,", "Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                ForEach(rows, id: \.0) { key, action in
                    GridRow {
                        Text(key).font(.system(.body, design: .monospaced).weight(.semibold))
                        Text(action)
                    }
                }
            }
            Text("Game controller: left stick = stick, right stick = rudder, triggers = throttle, A = guns, B = brakes.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 480)
    }
}
