import Foundation

/// Coordinates 9-point calibration flow.
/// Milestone 4 implementation.
final class CalibrationManager: ObservableObject {
    @Published var isCalibrating = false
    @Published var currentPointIndex = 0
    @Published var collectedPoints: [CalibrationPoint] = []

    func start() { isCalibrating = true; currentPointIndex = 0; collectedPoints = [] }
    func cancel() { isCalibrating = false; collectedPoints = [] }
    func complete() { isCalibrating = false }
}
