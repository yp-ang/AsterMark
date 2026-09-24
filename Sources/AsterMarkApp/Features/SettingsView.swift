import SwiftUI

/// Settings window (⌘,). Tabs are filled in during Phase 3 and Phase 8.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                placeholder("Canvas background and default sort order.")
            }
            Tab("Photographer", systemImage: "person.crop.square") {
                placeholder("Creator and copyright details embedded on export.")
            }
            Tab("Presets", systemImage: "aspectratio") {
                placeholder("Instagram and Facebook sizes.")
            }
        }
        .frame(width: 460, height: 260)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}
