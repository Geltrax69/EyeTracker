import SwiftUI

struct ContentView: View {
    @State private var cameraStatus: CameraStatus = .idle
    @State private var trackingStatus: TrackingStatus = .idle
    @State private var isCalibrating = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Eye Tracker")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Gaze-controlled cursor using your Mac camera")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            Divider()
                .padding(.vertical, 10)

            // Status Section
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(title: "Camera", label: cameraStatus.rawValue, color: cameraColor(cameraStatus))
                StatusRow(title: "Tracking", label: trackingStatus.rawValue, color: trackingColor(trackingStatus))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)

            Divider()
                .padding(.vertical, 10)

            // Control Buttons
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button(action: startTracking) {
                        Label("Start Tracking", systemImage: "play.fill")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(trackingStatus == .active || cameraStatus != .ready)

                    Button(action: stopTracking) {
                        Label("Stop Tracking", systemImage: "stop.fill")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(trackingStatus != .active)
                }

                Button(action: { isCalibrating = true }) {
                    Label("Calibrate", systemImage: "scope")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.bordered)
                .disabled(cameraStatus != .ready)
            }

            Spacer()

            // Footer
            VStack(spacing: 4) {
                Text("Privacy: All processing happens locally on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Emergency stop:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Cmd+Shift+E")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(width: 420, height: 420)
        .sheet(isPresented: $isCalibrating) {
            CalibrationView(isPresented: $isCalibrating)
        }
    }

    private func startTracking() {
        trackingStatus = .active
    }

    private func stopTracking() {
        trackingStatus = .idle
    }

    private func cameraColor(_ s: CameraStatus) -> Color {
        switch s {
        case .ready: return .green
        case .error, .denied: return .red
        case .initializing: return .yellow
        case .idle: return .gray
        }
    }

    private func trackingColor(_ s: TrackingStatus) -> Color {
        switch s {
        case .active: return .green
        case .calibrating: return .yellow
        case .idle: return .gray
        }
    }
}

// MARK: - Status Types

enum CameraStatus: String {
    case idle = "Idle"
    case initializing = "Initializing..."
    case ready = "Ready"
    case error = "Error"
    case denied = "Permission Denied"
}

enum TrackingStatus: String {
    case idle = "Idle"
    case active = "Active"
    case calibrating = "Calibrating..."
}

// MARK: - Status Row

struct StatusRow: View {
    let title: String
    let label: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
