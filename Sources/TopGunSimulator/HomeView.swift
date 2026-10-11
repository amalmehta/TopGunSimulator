import SwiftUI
import FlightCore

/// The start screen: flight school lessons, Top Gun missions and free flight.
struct HomeView: View {
    @EnvironmentObject var sim: SimulationController
    @State private var completed = LessonRecord.completed()

    private let groups = ["Airwork", "Takeoff & Landing", "Top Gun"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(groups, id: \.self) { group in
                    lessonGroup(group)
                }
                freeFlight
                HStack(spacing: 12) {
                    Button { sim.showHelp = true } label: { Label("Keyboard & gamepad controls", systemImage: "keyboard") }
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { completed = LessonRecord.completed() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "airplane")
                .font(.system(size: 40, weight: .bold))
                .rotationEffect(.degrees(-30))
                .foregroundStyle(LessonCategory.dogfight.color)
            VStack(alignment: .leading, spacing: 4) {
                Text("Top Gun Simulator").font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("Learn to fly in the trainer, then take the fighter through the canyon and into a dogfight.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let done = LessonCatalog.all.filter { completed.contains($0.id) }.count
            VStack(alignment: .trailing) {
                Text("\(done)/\(LessonCatalog.all.count)").font(.title2.bold().monospacedDigit())
                Text("lessons passed").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func lessonGroup(_ group: String) -> some View {
        let lessons = LessonCatalog.all.filter { $0.category.group == group }
        return VStack(alignment: .leading, spacing: 10) {
            Text(group == "Top Gun" ? "Top Gun" : "Flight School · \(group)").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(lessons) { lesson in
                    LessonCard(lesson: lesson, done: completed.contains(lesson.id)) { sim.start(.lesson(lesson)) }
                }
            }
        }
    }

    private var freeFlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Free Flight").font(.title3.bold())
            HStack(spacing: 12) {
                ForEach(AircraftSpec.Kind.allCases) { kind in
                    let spec = AircraftSpec.of(kind)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(spec.name, systemImage: kind == .trainer ? "airplane.circle" : "bolt.circle")
                            .font(.headline)
                        Text(kind == .trainer
                             ? "Forgiving high-wing trainer. Stalls at ~\(Int(spec.vStallKt)) kt, cruises at \(Int(spec.vCruiseKt)) kt."
                             : "Twin-engine fighter with fly-by-wire, afterburner and a 7.5 g limit.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("From the runway") { sim.start(.freeFlight(kind, airborne: false)) }
                            Button("In the air") { sim.start(.freeFlight(kind, airborne: true)) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                }
            }
        }
    }
}

struct LessonCard: View {
    let lesson: Lesson
    let done: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CategoryTag(category: lesson.category)
                    Spacer()
                    if done { Image(systemName: "checkmark.seal.fill").foregroundStyle(LessonCategory.takeoff.color) }
                    Text(lesson.aircraft == .trainer ? "Trainer" : "Fighter")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("\(lesson.number). \(lesson.title)").font(.headline)
                Text(lesson.summary).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(lesson.category.color.opacity(hover ? 0.18 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(lesson.category.color.opacity(hover ? 0.9 : 0.35), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct CategoryTag: View {
    let category: LessonCategory
    var body: some View {
        Label(category.rawValue, systemImage: category.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(category.color.opacity(0.18)))
            .foregroundStyle(category.color)
    }
}
