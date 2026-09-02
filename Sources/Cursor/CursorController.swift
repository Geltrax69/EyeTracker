import CoreGraphics

/// Moves the macOS mouse cursor using CGEvent.
/// Milestone 6 implementation; requires Accessibility permission.
final class CursorController {
    var isEnabled: Bool = false

    /// Move cursor to normalized screen coordinates (0...1).
    func moveTo(normalizedX x: Double, normalizedY y: Double) {
        guard isEnabled else { return }
        let screen = CGEventSource(stateID: .hidSystemState)
        let point = CGPoint(
            x: x * Double(CGDisplayBounds(CGMainDisplayID()).width),
            y: y * Double(CGDisplayBounds(CGMainDisplayID()).height)
        )
        let event = CGEvent(mouseEventSource: screen, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }
}
