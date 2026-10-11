import SwiftUI
import FlightCore

/// Right-hand sidebar: lesson, live instructor, 2D map and side profile.
struct SidebarView: View {
    @EnvironmentObject var sim: SimulationController
    @AppStorage(SettingsKey.instructorLevel) private var instructorLevel = InstructorLevel.explain.rawValue

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let lesson = sim.lesson {
                        LessonPanel(lesson: lesson, frame: sim.frame)
                    } else {
                        FreeFlightPanel(spec: sim.spec)
                    }
                    if instructorLevel != InstructorLevel.off.rawValue {
                        InstructorPanel(hints: sim.frame.hints, explain: instructorLevel == InstructorLevel.explain.rawValue)
                    }
                }
                .padding(12)
            }
            Divider()
            SectionHeader(title: "Map", symbol: "map")
            MapView(frame: sim.frame)
                .frame(height: 250)
            SectionHeader(title: "Side profile", symbol: "chart.line.uptrend.xyaxis")
            ProfileView(frame: sim.frame, showGlidepath: sim.lesson?.category == .landing || sim.spec.kind == .trainer)
                .frame(height: 130)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 5)
    }
}

struct LessonPanel: View {
    let lesson: Lesson
    let frame: FrameSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryTag(category: lesson.category)
                Spacer()
                Text("Step \(min(frame.lessonStepIndex + 1, lesson.steps.count))/\(lesson.steps.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(lesson.title).font(.title3.bold())
            ProgressView(value: Double(frame.lessonStepIndex), total: Double(lesson.steps.count))
                .tint(lesson.category.color)
            if frame.lessonStepIndex < lesson.steps.count {
                let step = lesson.steps[frame.lessonStepIndex]
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title).font(.headline).foregroundStyle(lesson.category.color)
                    Text(step.instruction).fixedSize(horizontal: false, vertical: true)
                    if let progress = frame.lessonProgressText {
                        Text(progress).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    if step.hold > 0 {
                        HStack(spacing: 6) {
                            Text("Hold").font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: min(frame.lessonHold, step.hold), total: step.hold)
                                .tint(lesson.category.color)
                            Text("\(Int(step.hold))s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if !step.tip.isEmpty {
                        Label(step.tip, systemImage: "graduationcap")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(lesson.category.color.opacity(0.1)))
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lesson.steps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 6) {
                        Image(systemName: i < frame.lessonStepIndex ? "checkmark.circle.fill" : (i == frame.lessonStepIndex ? "circle.inset.filled" : "circle"))
                            .foregroundStyle(i <= frame.lessonStepIndex ? lesson.category.color : .secondary)
                        Text(step.title).foregroundStyle(i == frame.lessonStepIndex ? .primary : .secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct FreeFlightPanel: View {
    let spec: AircraftSpec
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Free flight").font(.title3.bold())
            Text(spec.name).font(.headline).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow { Text("Stall"); Text("\(Int(spec.vStallKt)) kt") }
                GridRow { Text("Rotate"); Text("\(Int(spec.vRotateKt)) kt") }
                GridRow { Text("Best climb"); Text("\(Int(spec.vClimbKt)) kt") }
                GridRow { Text("Approach"); Text("\(Int(spec.vApproachKt)) kt") }
                GridRow { Text("Cruise"); Text("\(Int(spec.vCruiseKt)) kt") }
                GridRow { Text("Never exceed"); Text("\(Int(spec.vNeKt)) kt") }
            }
            .font(.system(.callout, design: .monospaced))
            Text("Runway 36 is 2,400 m long, heading north. The canyon starts 7 km north of the field. The PAPI lights left of the runway show two white and two red when you're on a 3° glidepath.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InstructorPanel: View {
    let hints: [Hint]
    let explain: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Instructor", systemImage: "person.wave.2").font(.headline)
            if hints.isEmpty {
                Text("Looking good. I'll speak up if something needs your attention.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(hints.prefix(4)) { hint in
                VStack(alignment: .leading, spacing: 3) {
                    Label(hint.text, systemImage: hint.severity.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(hint.severity.color)
                    if explain {
                        Text(hint.why).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(hint.severity.color.opacity(0.1)))
            }
        }
    }
}
