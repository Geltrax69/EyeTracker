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

    /// Solve a small dense system by Gaussian elimination with partial pivoting.
    static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix, b = rhs
        let n = b.count
        guard a.count == n, a.allSatisfy({ $0.count == n }) else { return nil }
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }),
                  abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot); b.swapAt(col, pivot)
            for row in (col + 1)..<n {
                let f = a[row][col] / a[col][col]
                guard f != 0 else { continue }
                for k in col..<n { a[row][k] -= f * a[col][k] }
                b[row] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }

    /// Least squares fit of `target ~= c0 + c1*f1 + c2*f2`, which is what calibration needs:
    /// it learns each feature's sign and scale from where you actually looked, so nobody has
    /// to guess whether head pitch adds to eye offset or cancels it.
    /// `ridge` keeps the solve stable when a feature barely varied across the samples.
    static func fitPlane(_ samples: [(f1: Double, f2: Double, target: Double)],
                         ridge: Double = 1e-6) -> (c0: Double, c1: Double, c2: Double)? {
        guard samples.count >= 3 else { return nil }
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var atb = [Double](repeating: 0, count: 3)
        for s in samples {
            let row = [1.0, s.f1, s.f2]
            for i in 0..<3 {
                for j in 0..<3 { ata[i][j] += row[i] * row[j] }
                atb[i] += row[i] * s.target
            }
        }
        for i in 0..<3 { ata[i][i] += ridge }
        guard let c = solve(ata, atb) else { return nil }
        return (c[0], c[1], c[2])
    }

    /// Root-mean-square error of a fit against the samples it was built from.
    static func rmsError(_ samples: [(f1: Double, f2: Double, target: Double)],
                         _ fit: (c0: Double, c1: Double, c2: Double)) -> Double {
        guard samples.isEmpty == false else { return 0 }
        let total = samples.reduce(0.0) { sum, s in
            let predicted = fit.c0 + fit.c1 * s.f1 + fit.c2 * s.f2
            return sum + (predicted - s.target) * (predicted - s.target)
        }
        return (total / Double(samples.count)).squareRoot()
    }
}
