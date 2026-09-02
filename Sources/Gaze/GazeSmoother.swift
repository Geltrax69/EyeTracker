import Foundation

/// Low-pass / EMA filter for noisy gaze estimates.
/// Milestone 7 implementation.
final class GazeSmoother {
    var alpha: Double = 0.3
    private var lastX: Double = 0.5
    private var lastY: Double = 0.5

    func smooth(x: Double, y: Double) -> (x: Double, y: Double) {
        lastX = lastX * (1 - alpha) + x * alpha
        lastY = lastY * (1 - alpha) + y * alpha
        return (lastX, lastY)
    }

    func reset() {
        lastX = 0.5
        lastY = 0.5
    }
}
