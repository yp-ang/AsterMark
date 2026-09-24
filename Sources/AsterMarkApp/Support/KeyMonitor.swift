import AppKit
import AsterCore

/// Handles bare-key shortcuts for the main window without stealing keys from text fields.
/// Menu items can't use bare keys safely, so this runs as a local event monitor instead.
///
/// With a watermark selected: arrows nudge (⇧ ×10), 1–9 snap to anchors, ⌫ removes, esc deselects.
/// Otherwise arrows move between photos. Always: tab cycles watermarks, \ before/after,
/// H hides handles, X excludes.
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
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let session = model.session,
              let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
              !(window.firstResponder is NSText),
              modifiers.subtracting(.shift).isEmpty
        else { return false }
        let shift = modifiers.contains(.shift)
        let step = shift ? 10.0 : 1.0
        let layerSelected = model.hasSelectedLayer

        switch event.specialKey {
        case .rightArrow?:
            if layerSelected { model.nudgeSelected(dx: step, dy: 0) } else if !shift { session.goToNext() }
            return true
        case .leftArrow?:
            if layerSelected { model.nudgeSelected(dx: -step, dy: 0) } else if !shift { session.goToPrevious() }
            return true
        case .upArrow?:
            guard layerSelected else { return false }
            model.nudgeSelected(dx: 0, dy: -step)
            return true
        case .downArrow?:
            guard layerSelected else { return false }
            model.nudgeSelected(dx: 0, dy: step)
            return true
        case .tab?, .backTab?:
            model.cycleSelection(backwards: shift || event.specialKey == .backTab)
            return true
        case .delete?, .deleteForward?, .backspace?:
            guard layerSelected else { return false }
            model.removeSelected()
            return true
        default:
            break
        }
        if event.keyCode == 53 { // esc
            guard session.selectedLayerID != nil else { return false }
            session.selectedLayerID = nil
            return true
        }

        guard !shift, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if layerSelected, let digit = Int(key), let anchor = Anchor(keypadDigit: digit) {
            model.anchorSelected(anchor)
            return true
        }
        switch key {
        case "x":
            let keys = session.targetKeys
            let excluded = keys.allSatisfy { session.editor.project.edit(for: $0).isExcluded }
            session.editor.setExcluded(!excluded, for: keys)
        case "\\":
            session.showWatermarks.toggle()
        case "h":
            session.showHandles.toggle()
        default:
            return false
        }
        return true
    }
}
