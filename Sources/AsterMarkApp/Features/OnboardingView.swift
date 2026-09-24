import SwiftUI

/// Three quiet steps on first launch. Skippable, and shown once (Help ▸ Show Welcome brings it back).
struct OnboardingView: View {
    static let seenKey = "hasSeenOnboarding"
    static let showNotification = Notification.Name("AsterMark.showOnboarding")
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to AsterMark").font(.largeTitle.weight(.semibold))
            Text("Brand a whole shoot in minutes. Your original photos are never changed.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 18) {
                step("1", "Drop your logo", "Drag a PNG, PDF or SVG onto Watermarks in the sidebar.", "seal")
                step("2", "Open a folder", "Drop a folder of exported photos onto the window. Drag your logo onto the first photo and it appears on all of them.", "photo.stack")
                step("3", "Review and export", "Fix the few that need it (G shows them all), crop for Instagram with C, then press ⌘E.", "square.and.arrow.up")
            }
            .frame(maxWidth: 440)
            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: Self.seenKey)
                onDone()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(36)
        .frame(width: 560)
    }

    private func step(_ number: String, _ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(detail)")
    }
}

/// Help ▸ Keyboard Shortcuts.
struct ShortcutsView: View {
    private let groups: [(String, [(String, String)])] = [
        ("Photos", [("← / →", "Previous / next photo"), ("⌘← / ⌘→", "Previous / next needing review"),
                    ("G", "Review grid"), ("X", "Exclude or include"), ("⌘D", "Apply layout to all photos"),
                    ("⇧⌘C / ⇧⌘V", "Copy / paste layout")]),
        ("Watermark (selected)", [("Drag", "Move (⌘ turns snapping off)"), ("Drag a corner", "Resize (⌥ from the centre)"),
                                  ("Round handle", "Rotate (⇧ for 15° steps)"), ("Arrows", "Nudge (⇧ ×10)"),
                                  ("1–9", "Snap to a position"), ("Tab", "Next watermark"), ("⌫", "Remove"),
                                  ("Esc", "Deselect")]),
        ("View", [("⌘0 / ⌘1", "Fit / actual size"), ("⌘= / ⌘−", "Zoom in / out"), ("\\", "Before / after"),
                  ("H", "Hide handles"), ("O", "Safe zones")]),
        ("Crop & export", [("C", "Crop (on an output)"), ("↩ / Esc", "Finish / cancel crop"), ("⌘E", "Export"),
                           ("⇧⌘E", "Export again"), ("⌘Z / ⇧⌘Z", "Undo / redo")]),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(groups, id: \.0) { title, items in
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    ForEach(items, id: \.0) { key, action in
                        HStack(alignment: .firstTextBaseline) {
                            Text(key).font(.body.monospaced()).frame(width: 110, alignment: .leading)
                            Text(action).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 280, alignment: .leading)
            }
        }
        .padding(24)
    }
}
