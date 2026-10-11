import SwiftUI
import FlightCore

/// All user preferences live in UserDefaults under these keys. Views bind with @AppStorage;
/// the simulation reads a snapshot with `SimSettings.current`.
enum SettingsKey {
    static let autoRudder = "autoRudder"
    static let invertPitch = "invertPitch"
    static let stickSensitivity = "stickSensitivity"
    static let keyboardCentering = "keyboardCentering"
    static let instructorLevel = "instructorLevel"
    static let showHUD = "showHUD"
    static let showInstruments = "showInstruments"
    static let showSidebar = "showSidebar"
    static let metricUnits = "metricUnits"
    static let fieldOfView = "fieldOfView"
    static let windSpeedKt = "windSpeedKt"
    static let windFromDeg = "windFromDeg"
    static let turbulence = "turbulence"
    static let banditSkill = "banditSkill"
    static let completedLessons = "completedLessons"
}

enum InstructorLevel: String, CaseIterable, Identifiable {
    case off, hints, explain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .hints: return "Hints"
        case .explain: return "Hints + why"
        }
    }
}

struct SimSettings {
    var autoRudder: Bool
    var invertPitch: Bool
    var stickSensitivity: Double
    var keyboardCentering: Double
    var instructorLevel: InstructorLevel
    var metricUnits: Bool
    var fieldOfView: Double
    var windSpeedKt: Double
    var windFromDeg: Double
    var turbulence: Double
    var banditSkill: Double

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.autoRudder: true,
            SettingsKey.invertPitch: false,
            SettingsKey.stickSensitivity: 1.0,
            SettingsKey.keyboardCentering: 1.0,
            SettingsKey.instructorLevel: InstructorLevel.explain.rawValue,
            SettingsKey.showHUD: true,
            SettingsKey.showInstruments: true,
            SettingsKey.showSidebar: true,
            SettingsKey.metricUnits: false,
            SettingsKey.fieldOfView: 65.0,
            SettingsKey.windSpeedKt: 0.0,
            SettingsKey.windFromDeg: 360.0,
            SettingsKey.turbulence: 0.0,
            SettingsKey.banditSkill: 0.6,
        ])
    }

    static var current: SimSettings {
        let d = UserDefaults.standard
        return SimSettings(
            autoRudder: d.bool(forKey: SettingsKey.autoRudder),
            invertPitch: d.bool(forKey: SettingsKey.invertPitch),
            stickSensitivity: d.double(forKey: SettingsKey.stickSensitivity),
            keyboardCentering: d.double(forKey: SettingsKey.keyboardCentering),
            instructorLevel: InstructorLevel(rawValue: d.string(forKey: SettingsKey.instructorLevel) ?? "") ?? .explain,
            metricUnits: d.bool(forKey: SettingsKey.metricUnits),
            fieldOfView: d.double(forKey: SettingsKey.fieldOfView),
            windSpeedKt: d.double(forKey: SettingsKey.windSpeedKt),
            windFromDeg: d.double(forKey: SettingsKey.windFromDeg),
            turbulence: d.double(forKey: SettingsKey.turbulence),
            banditSkill: d.double(forKey: SettingsKey.banditSkill))
    }

    var wind: WindModel {
        WindModel(speed: windSpeedKt * Units.knot, fromHeadingDeg: windFromDeg, turbulence: turbulence)
    }
}

/// Lesson completion record (per user, local only).
enum LessonRecord {
    static func completed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: SettingsKey.completedLessons) ?? [])
    }
    static func markCompleted(_ id: String) {
        var s = completed(); s.insert(id)
        UserDefaults.standard.set(Array(s).sorted(), forKey: SettingsKey.completedLessons)
    }
    static func reset() { UserDefaults.standard.removeObject(forKey: SettingsKey.completedLessons) }
}

/// Unit formatting that respects the metric toggle.
struct UnitFormatter {
    var metric: Bool
    func altitude(_ ft: Double) -> String {
        metric ? "\(Int((ft * Units.foot).rounded())) m" : "\(Int(ft.rounded())) ft"
    }
    func speed(_ kt: Double) -> String {
        metric ? "\(Int((kt * Units.knot * 3.6).rounded())) km/h" : "\(Int(kt.rounded())) kt"
    }
    func vertical(_ fpm: Double) -> String {
        metric ? String(format: "%+.1f m/s", fpm * Units.feetPerMinute) : "\(Int(fpm.rounded())) fpm"
    }
}
