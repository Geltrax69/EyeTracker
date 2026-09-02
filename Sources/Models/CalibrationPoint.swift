import Foundation

/// One on-screen calibration point + the eye/head measurements collected while
/// the user looked at it.
struct CalibrationPoint {
    /// Target position on the screen, normalized 0...1.
    let screenX: Double
    let screenY: Double
    /// Multiple measurements to filter out unstable samples.
    var samples: [EyeFeatures] = []

    /// Stable mean of samples; returns nil if not enough valid samples.
    var averagedFeatures: EyeFeatures? {
        let valid = samples.filter { $0.faceDetected }
        guard valid.count >= 3 else { return nil }
        return EyeFeatures(
            leftIrisX: valid.map(\.leftIrisX).reduce(0, +) / Double(valid.count),
            leftIrisY: valid.map(\.leftIrisY).reduce(0, +) / Double(valid.count),
            rightIrisX: valid.map(\.rightIrisX).reduce(0, +) / Double(valid.count),
            rightIrisY: valid.map(\.rightIrisY).reduce(0, +) / Double(valid.count),
            eyeCenterX: valid.map(\.eyeCenterX).reduce(0, +) / Double(valid.count),
            eyeCenterY: valid.map(\.eyeCenterY).reduce(0, +) / Double(valid.count),
            headYaw: valid.map(\.headYaw).reduce(0, +) / Double(valid.count),
            headPitch: valid.map(\.headPitch).reduce(0, +) / Double(valid.count),
            headRoll: valid.map(\.headRoll).reduce(0, +) / Double(valid.count),
            faceDetected: true
        )
    }
}
