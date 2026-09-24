import AppKit

/// Handles bare-key shortcuts (← → X) for the main window without stealing keys from text fields.
/// Menu items can't use bare arrow keys safely, so this runs as a local event monitor instead.
@MainActor
final class KeyMonitor {
    private var monitor: Any?

    func install(model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { Self.handle(event, model: model) }
            return handled ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func handle(_ event: NSEvent, model: AppModel) -> Bool {
        guard let session = model.session,
              let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
              !(window.firstResponder is NSText),
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        else { return false }

        switch event.specialKey {
        case .rightArrow?:
            session.goToNext()
            return true
        case .leftArrow?:
            session.goToPrevious()
            return true
        default:
            break
        }
        if event.charactersIgnoringModifiers?.lowercased() == "x" {
            let keys = session.targetKeys
            let excluded = keys.allSatisfy { session.editor.project.edit(for: $0).isExcluded }
            session.editor.setExcluded(!excluded, for: keys)
            return true
        }
        return false
    }
}
