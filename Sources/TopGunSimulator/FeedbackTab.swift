import SwiftUI
import AppKit

/// Small, out-of-the-way feedback button. Notes are saved locally as JSON lines.
struct FeedbackTab: View {
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Label("Feedback", systemImage: "bubble.left")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .opacity(0.8)
        .help("Send feedback")
        .popover(isPresented: $open, arrowEdge: .top) { FeedbackForm(isOpen: $open) }
    }
}

enum FeedbackStore {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Top Gun Simulator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("feedback.jsonl")
    }

    static func save(kind: String, text: String) throws {
        let entry: [String: String] = ["date": ISO8601DateFormatter().string(from: Date()), "kind": kind, "text": text]
        var line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL)
        }
    }
}

private struct FeedbackForm: View {
    @Binding var isOpen: Bool
    @State private var kind = "Idea"
    @State private var text = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feedback").font(.headline)
            Picker("", selection: $kind) {
                Text("Idea").tag("Idea"); Text("Bug").tag("Bug"); Text("Flight model").tag("Flight model")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextEditor(text: $text)
                .font(.body)
                .frame(width: 300, height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            HStack {
                Button("Show file") { NSWorkspace.shared.activateFileViewerSelecting([FeedbackStore.fileURL]) }
                    .buttonStyle(.link)
                Spacer()
                if saved { Text("Saved, thanks!").foregroundStyle(.green).font(.caption) }
                Button("Save") {
                    try? FeedbackStore.save(kind: kind, text: text)
                    saved = true
                    text = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { isOpen = false; saved = false }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }
}
