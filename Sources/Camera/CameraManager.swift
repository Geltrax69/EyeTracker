import AVFoundation
import Combine
import CoreImage

/// Manages webcam capture via AVCaptureSession.
/// Phase 2 will add real camera access; this is a stub for Milestone 1.
final class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var permissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var latestFrame: CGImage?

    /// Returns the most recent camera frame as a CGImage, or nil.
    var currentFrame: CGImage? { latestFrame }

    func start() {
        permissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard permissionStatus == .authorized else { return }
        isRunning = true
    }

    func stop() {
        isRunning = false
        latestFrame = nil
    }
}
