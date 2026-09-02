import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var tracker = GazeTracker()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                CameraPreview(session: tracker.session)
                FaceOverlay(debug: tracker.debug)
            }
            .aspectRatio(tracker.videoAspect, contentMode: .fit)
            .frame(maxHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                Label(tracker.faceDetected ? "Face" : "No face",
                      systemImage: tracker.faceDetected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption).padding(6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(tracker.faceDetected ? .green : .orange)
                    .padding(6)
            }

            Text(tracker.status).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Text("Permission: \(permissionText)").font(.caption)
                Text("Camera: \(tracker.cameraName)").font(.caption)
                if tracker.permission == .denied || tracker.permission == .restricted {
                    Button("Open Settings") { tracker.openCameraSettings() }.font(.caption)
                }
            }
            .foregroundStyle(.secondary)

            SignalReadout(debug: tracker.debug)

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    GazeDot(point: tracker.gaze).frame(width: 180, height: 100)
                    Text("estimated gaze on screen").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    EyeZoom(debug: tracker.debug).frame(width: 180, height: 100)
                    Text("pupil inside each eye").font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(tracker.isRunning ? "Stop" : "Start Tracking") {
                    tracker.isRunning ? tracker.stop() : tracker.start()
                }
                .buttonStyle(.borderedProminent)
                Button("Re-center") { tracker.recenter() }.disabled(!tracker.isRunning)
                Toggle("Move cursor", isOn: $tracker.controlsCursor).disabled(!tracker.isRunning)
            }

            HStack(spacing: 12) {
                Toggle("Blink to re-center", isOn: $tracker.blinkRecenters)
                Text(tracker.blinking ? "blink" : "eyes open")
                    .font(.caption).foregroundStyle(tracker.blinking ? .yellow : .secondary)
                Text("\(tracker.blinkCount) blinks").font(.caption).foregroundStyle(.secondary)
            }

            GroupBox("Tuning") {
                Slider(value: $tracker.gainX, in: -20...20) { Text("Eye X \(tracker.gainX, specifier: "%.1f")") }
                Slider(value: $tracker.gainY, in: -40...40) { Text("Eye Y \(tracker.gainY, specifier: "%.1f")") }
                Slider(value: $tracker.yawGain, in: -12...12) { Text("Head yaw \(tracker.yawGain, specifier: "%.1f")") }
                Slider(value: $tracker.pitchGain, in: -12...12) { Text("Head pitch \(tracker.pitchGain, specifier: "%.1f")") }
                Slider(value: $tracker.headDeadzone, in: 0...0.25) { Text("Head deadzone \(tracker.headDeadzone, specifier: "%.2f")") }
                Slider(value: $tracker.smoothing, in: 0.02...1) { Text("Smoothing \(tracker.smoothing, specifier: "%.2f")") }
            }

            Text("Cursor control pauses for 3s if you move the mouse yourself.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 480)
        .onAppear { tracker.refreshDiagnostics() }
    }

    private var permissionText: String {
        switch tracker.permission {
        case .authorized: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }
}

/// Face box, eye outlines, pupils and a per-eye arrow, drawn over the camera image.
/// Vision's origin is bottom-left, the view's is top-left, hence every `1 - y`.
struct FaceOverlay: View {
    let debug: FaceDebug?

    var body: some View {
        Canvas { ctx, size in
            guard let d = debug else { return }
            func pt(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
            }

            let box = CGRect(x: d.box.minX * size.width,
                             y: (1 - d.box.maxY) * size.height,
                             width: d.box.width * size.width,
                             height: d.box.height * size.height)
            ctx.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(.green.opacity(0.7)), lineWidth: 1.5)

            for (eye, pupil, offset) in [(d.leftEye, d.leftPupil, d.leftOffset),
                                         (d.rightEye, d.rightPupil, d.rightOffset)] {
                guard eye.count > 2 else { continue }
                var path = Path()
                path.addLines(eye.map(pt))
                path.closeSubpath()
                ctx.stroke(path, with: .color(.cyan), lineWidth: 1.5)

                guard let p = pupil else { continue }
                let c = pt(p)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                         with: .color(.yellow))

                // Arrow from the eye's centre toward where the pupil sits inside it.
                guard let o = offset else { continue }
                let bounds = path.boundingRect
                let mid = CGPoint(x: bounds.midX, y: bounds.midY)
                let len = max(bounds.width, 30)
                let tip = CGPoint(x: mid.x + o.x * 3 * len, y: mid.y - o.y * 3 * len)
                var arrow = Path()
                arrow.move(to: mid)
                arrow.addLine(to: tip)
                ctx.stroke(arrow, with: .color(.red), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)),
                         with: .color(.red))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The raw numbers calibration will be fitted from.
struct SignalReadout: View {
    let debug: FaceDebug?
    var body: some View {
        let d = debug
        HStack(spacing: 14) {
            Text("L \(fmt(d?.leftOffset))")
            Text("R \(fmt(d?.rightOffset))")
            Text("open \(d?.openness.map { String(format: "%.2f", $0) } ?? "—")")
            Text("yaw \(d.map { String(format: "%+.2f", $0.yaw) } ?? "—")")
            Text("pitch \(d.map { String(format: "%+.2f", $0.pitch) } ?? "—")")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    private func fmt(_ p: CGPoint?) -> String {
        p.map { String(format: "%+.3f,%+.3f", $0.x, $0.y) } ?? "—,—"
    }
}

/// Each eye normalized to its own square, so you can watch the pupil move even
/// when the eye is only 20 pixels wide in the camera image.
struct EyeZoom: View {
    let debug: FaceDebug?
    var body: some View {
        HStack(spacing: 8) {
            eye("L", debug?.leftOffset)
            eye("R", debug?.rightOffset)
        }
    }
    private func eye(_ label: String, _ o: CGPoint?) -> some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 4).stroke(.secondary)
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(.secondary.opacity(0.3))
                if let o {
                    // offsets are eye-widths from centre; x spans about +/-0.4, y much less
                    Circle().fill(.yellow).frame(width: 10, height: 10)
                        .position(x: geo.size.width * (0.5 + o.x * 1.5),
                                  y: geo.size.height * (0.5 - o.y * 1.5))
                }
                Text(label).font(.caption2).foregroundStyle(.secondary)
                    .position(x: 10, y: 10)
            }
        }
    }
}

/// Where the tracker thinks you are looking, as a fraction of the screen.
struct GazeDot: View {
    let point: CGPoint
    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6).stroke(.secondary)
                .overlay(alignment: .topLeading) {
                    Circle().fill(.blue).frame(width: 14, height: 14)
                        .offset(x: geo.size.width * point.x - 7, y: geo.size.height * point.y - 7)
                        .animation(.linear(duration: 0.05), value: point)
                }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // Vision reads the unmirrored buffer; mirror the preview to match, or the
        // overlay lands on the wrong eye.
        if let c = layer.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = false
        }
        view.layer = layer
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview { ContentView() }
