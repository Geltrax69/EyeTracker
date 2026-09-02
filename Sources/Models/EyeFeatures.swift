import Foundation

/// Feature vector describing eyes + head pose for one camera frame.
/// Used downstream by GazeEstimator and CalibrationManager.
struct EyeFeatures: Equatable {
    /// Normalized left iris position (0...1) in face bounding-box space.
    var leftIrisX: Double = 0
    var leftIrisY: Double = 0
    /// Normalized right iris position (0...1).
    var rightIrisX: Double = 0
    var rightIrisY: Double = 0
    /// Average iris position (eye center).
    var eyeCenterX: Double = 0
    var eyeCenterY: Double = 0
    /// Head pose in radians. yaw = left/right, pitch = up/down, roll = tilt.
    var headYaw: Double = 0
    var headPitch: Double = 0
    var headRoll: Double = 0
    /// True if a face was detected in the source frame.
    var faceDetected: Bool = false

    static let empty = EyeFeatures()
}
