import AsterCore
import SwiftUI

@main
struct AsterMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("AsterMark", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .task { await model.start() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(model: model)
            SidebarCommands()
            InspectorCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (e.g. `swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Folders or images dropped on the Dock icon, or opened with "Open With ▸ AsterMark".
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in await AppModel.shared.handleDroppedURLs(urls) }
    }

    /// Writes any pending autosave before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppModel.shared.flush()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// File, Edit and Photo menu commands.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { model.showOpenPanel() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recents) { summary in
                    Button(summary.displayName) { Task { await model.open(summary) } }
                }
                if !model.recents.isEmpty {
                    Divider()
                }
                Button("Clear Menu") {
                    Task { for summary in model.recents { await model.forget(summary) } }
                }
                .disabled(model.recents.isEmpty)
            }
            Divider()
            Button("Import Watermark…") { model.showImportPanel() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Close Album") { Task { await model.closeAlbum() } }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.session == nil)
        }

        // Album edits use the app's own undo manager (see AppModel.undoManager).
        CommandGroup(replacing: .undoRedo) {
            let _ = model.undoRevision
            Button(model.undoManager.canUndo ? "Undo \(model.undoManager.undoActionName)" : "Undo") {
                model.undoManager.undo()
            }
            .keyboardShortcut("z")
            .disabled(!model.undoManager.canUndo)
            Button(model.undoManager.canRedo ? "Redo \(model.undoManager.redoActionName)" : "Redo") {
                model.undoManager.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.undoManager.canRedo)
        }

        CommandGroup(after: .toolbar) {
            let session = model.session
            Button("Zoom to Fit") { session?.zoomToFit() }
                .keyboardShortcut("0")
            Button("Actual Size") { session?.zoomToActualSize() }
                .keyboardShortcut("1")
            Button("Zoom In") { session?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { session?.zoomOut() }
                .keyboardShortcut("-")
            Divider()
            Button(session?.showWatermarks == false ? "Show Watermarks  \\" : "Hide Watermarks  \\") {
                session?.showWatermarks.toggle()
            }
            .disabled(session == nil)
            Button(session?.showHandles == false ? "Show Handles  H" : "Hide Handles  H") {
                session?.showHandles.toggle()
            }
            .disabled(session == nil)
            Divider()
        }

        CommandMenu("Photo") {
            let session = model.session
            Button("Next Photo  →") { session?.goToNext() }
                .disabled(session == nil)
            Button("Previous Photo  ←") { session?.goToPrevious() }
                .disabled(session == nil)
            // ⌘← / ⌘→ are handled by KeyMonitor so they keep working as usual inside text fields.
            Button("Next Needing Review  ⌘→") { session?.goToNextNeedingReview() }
                .disabled((session?.needsReviewCount ?? 0) == 0)
            Button("Previous Needing Review  ⌘←") { session?.goToNextNeedingReview(forward: false) }
                .disabled((session?.needsReviewCount ?? 0) == 0)
            Button(session?.viewMode == .grid ? "Show Photo  G" : "Show Review Grid  G") {
                session?.viewMode = session?.viewMode == .grid ? .canvas : .grid
            }
            .disabled(session == nil)
            Divider()
            Button("Apply Layout to All Photos") { model.requestApplyToAll() }
                .keyboardShortcut("d")
                .disabled(session == nil)
            Button("Copy Layout") {
                if let key = session?.editor.currentPhoto?.relativePath { session?.editor.copyLayout(from: key) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(session?.editor.currentPhoto == nil)
            Button("Paste Layout") {
                if let session { session.editor.pasteLayout(to: session.targetKeys) }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(session?.editor.clipboard == nil)
            Button("Reset to Album Default") {
                if let session { session.editor.resetToDefault(session.targetKeys) }
            }
            .disabled(session == nil)
            Divider()
            Button("Exclude from Export  X") {
                if let session {
                    let keys = session.targetKeys
                    let excluded = keys.allSatisfy { session.editor.project.edit(for: $0).isExcluded }
                    session.editor.setExcluded(!excluded, for: keys)
                }
            }
            .disabled(session == nil)
        }
    }
}
