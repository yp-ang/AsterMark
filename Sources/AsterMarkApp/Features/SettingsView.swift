import AppKit
import AsterCore
import SwiftUI

/// Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Photographer", systemImage: "person.crop.square") { PhotographerSettings() }
            Tab("Presets", systemImage: "aspectratio") { PresetSettings() }
        }
        .frame(width: 520, height: 360)
    }
}

private struct GeneralSettings: View {
    @AppStorage("canvasBackground") private var background = CanvasBackground.grey

    var body: some View {
        Form {
            Picker("Canvas background", selection: $background) {
                ForEach(CanvasBackground.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("A neutral grey makes watermark opacity easiest to judge.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// Stored now; embedded as IPTC metadata on export in Phase 8.
private struct PhotographerSettings: View {
    @AppStorage("profile.creator") private var creator = ""
    @AppStorage("profile.copyright") private var copyright = ""
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.website") private var website = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $creator, prompt: Text("Jane Doe"))
                TextField("Copyright notice", text: $copyright, prompt: Text("© 2026 Jane Doe Photography"))
                TextField("Email", text: $email)
                TextField("Website", text: $website)
            } footer: {
                Text("Added to exported photos' metadata so your work stays credited.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PresetSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(SizePreset.builtIn) { preset in
                    LabeledContent(preset.name, value: detail(preset))
                }
            } footer: {
                HStack {
                    Text("Platforms change sizes. Edit presets.json to adjust or add your own.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show presets.json") { revealPresetsFile() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func detail(_ preset: SizePreset) -> String {
        if let w = preset.pixelWidth, let h = preset.pixelHeight { return "\(w) × \(h)" }
        if let edge = preset.longEdge { return "\(edge) px long edge" }
        return "Original"
    }

    /// Writes the built-in presets as a starting point if the file doesn't exist, then reveals it.
    private func revealPresetsFile() {
        let url = model.paths.presetsFile
        if !FileManager.default.fileExists(atPath: url.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(SizePreset.builtIn).write(to: url, options: .atomic)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
