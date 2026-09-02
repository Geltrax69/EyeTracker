import AVFoundation
import AppKit

/// Centralized permission checks for camera and accessibility.
/// Milestone 2 / Milestone 6 full implementation.
final class PermissionsManager {
    enum CameraPermission {
        case granted, denied, notDetermined
    }

    static func cameraStatus() -> CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    static func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }

    /// True if the app has been granted Accessibility (Automation) permission.
    static func hasAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
