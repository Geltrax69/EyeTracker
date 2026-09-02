import Foundation

/// Pure gaze math. No frameworks, so it is testable with `swiftc` alone (see Tests/main.swift).
enum GazeMath {
    static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    /// Linear map from a raw signal to a normalized screen axis.
    /// ponytail: affine only. Calibration replaces center/gain with a least-squares fit.
    static func map(raw: Double, center: Double, gain: Double) -> Double {
        clamp01(0.5 + (raw - center) * gain)
    }

    /// Exponential moving average. alpha 0 = frozen, 1 = no smoothing.
    static func ema(_ prev: Double, _ next: Double, alpha: Double) -> Double {
        prev + (next - prev) * alpha
    }

    static func distance(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1)).squareRoot()
    }

    /// Pupil position measured from the line between the eye corners, in units of eye width.
    /// Corners are bone; eyelids are not — the eyelid box shrinks when you look down, which
    /// hides vertical gaze almost entirely. Roughly -0.5...0.5 horizontally, less vertically.
    /// `aspect` (image width/height) makes x and y the same physical unit.
    static func cornerRelative(pupil p: (x: Double, y: Double),
                               eye: [(x: Double, y: Double)],
                               aspect: Double) -> (x: Double, y: Double)? {
        guard eye.count > 2 else { return nil }
        let pts = eye.map { (x: $0.x * aspect, y: $0.y) }
        guard let left = pts.min(by: { $0.x < $1.x }), let right = pts.max(by: { $0.x < $1.x }) else { return nil }
        let width = distance((left.x, left.y), (right.x, right.y))
        guard width > 1e-6 else { return nil }
        let mid = ((left.x + right.x) / 2, (left.y + right.y) / 2)
        return ((p.x * aspect - mid.0) / width, (p.y - mid.1) / width)
    }

    /// Eye openness: outline height over corner-to-corner width. About 0.3 open, near 0 shut.
    /// The cheap standard blink signal — no extra model, just the landmarks already on hand.
    static func eyeAspectRatio(eye: [(x: Double, y: Double)], aspect: Double) -> Double? {
        guard eye.count > 2 else { return nil }
        let pts = eye.map { (x: $0.x * aspect, y: $0.y) }
        guard let left = pts.min(by: { $0.x < $1.x }), let right = pts.max(by: { $0.x < $1.x }),
              let top = pts.map(\.y).max(), let bottom = pts.map(\.y).min() else { return nil }
        let width = distance((left.x, left.y), (right.x, right.y))
        guard width > 1e-6 else { return nil }
        return (top - bottom) / width
    }

    /// Zero below `threshold`, then continues from zero above it. Lets head turn extend the
    /// cursor's reach past what the eyes alone can cover, without small head drift moving it.
    static func deadzone(_ v: Double, threshold: Double) -> Double {
        v > threshold ? v - threshold : (v < -threshold ? v + threshold : 0)
    }
}
