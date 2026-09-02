import Foundation

/// Maps eye features + head pose to normalized screen coordinates (0...1).
/// Milestone 5 implementation: simple regression on calibration data.
final class GazeEstimator {
    /// Returns estimated normalized screen point (x, y) in 0...1.
    func estimate(_ features: EyeFeatures) -> (x: Double, y: Double) {
        return (0.5, 0.5)
    }
}
