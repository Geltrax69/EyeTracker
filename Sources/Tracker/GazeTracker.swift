import AVFoundation
import Vision
import AppKit
import Combine

/// What Vision saw in the last frame, in image-normalized coords (0...1, origin bottom-left).
/// Published so the UI can draw it — if you cannot see the pupils, you cannot calibrate them.
struct FaceDebug {
    var box: CGRect = .zero
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    var leftPupil: CGPoint?
    var rightPupil: CGPoint?
    /// Pupil offset from the eye-corner line, in eye widths. The raw gaze signal.
    /// ~-0.5...0.5 horizontally, and a good deal smaller vertically.
    var leftOffset: CGPoint?
    var rightOffset: CGPoint?
    var yaw: Double = 0
    var pitch: Double = 0
    /// Eye openness, ~0.3 open and near 0 shut. nil when the outline is unusable.
    var openness: Double?
}

/// Camera -> Vision face landmarks -> cursor. One object, because splitting it into
/// four would only mean four files that all change together.
final class GazeTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // Live state for the UI
    @Published var status = "Idle"
    @Published var faceDetected = false
    @Published var gaze: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var isRunning = false
    @Published var controlsCursor = false
    @Published var debug: FaceDebug?
    @Published var videoAspect: Double = 16.0 / 9.0
    @Published var blinking = false
    @Published var blinkRecenters = true
    @Published var blinkCount = 0
    @Published var permission: AVAuthorizationStatus = .notDetermined
    @Published var cameraName = "—"

    // Tuning knobs. Real cameras and real faces differ; calibration will set these.
    @Published var gainX: Double = -3.0
    @Published var gainY: Double = 8.0
    /// Head turn extends the cursor's reach where the pupils run out of travel.
    @Published var yawGain: Double = -2.5
    @Published var pitchGain: Double = 2.5
    @Published var smoothing: Double = 0.25
    /// Radians of head movement to ignore before it starts pushing the cursor.
    @Published var headDeadzone: Double = 0.06

    private(set) var centerX: Double = 0.5
    private(set) var centerY: Double = 0.5
    private var rawX: Double = 0.5
    private var rawY: Double = 0.5

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "gaze.frames")
    private var recenterFrames = 0
    private var recenterAccum = (x: 0.0, y: 0.0)

    /// Blink detection. A blink is a drop below `blinkThreshold` for a couple of frames;
    /// the eyes are shut during it, so recentering uses the last sample from before it.
    let blinkThreshold = 0.17
    private var closedFrames = 0
    private var blinkArmed = true
    private var lastOpenSignal: (x: Double, y: Double)?

    // Safety valve: if the real cursor is far from where we last put it, the human moved
    // the mouse — hand control back for a moment instead of fighting them.
    private var lastWarp: CGPoint = .zero
    private var yieldUntil = Date.distantPast

    // MARK: - Permissions / devices

    func refreshDiagnostics() {
        permission = AVCaptureDevice.authorizationStatus(for: .video)
        cameraName = Self.camera()?.localizedName ?? "none found"
        if permission == .denied || permission == .restricted {
            status = "Camera access denied — open Settings and enable it, then press Start"
        }
    }

    /// `AVCaptureDevice.default` misses Continuity and external cameras on some Macs.
    static func camera() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices.first ?? AVCaptureDevice.default(for: .video)
    }

    func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Lifecycle

    func start() {
        refreshDiagnostics()
        switch permission {
        case .denied, .restricted:
            status = "Camera access denied — open Settings and enable it, then press Start"
        case .authorized:
            begin()
        default:
            status = "Waiting for camera permission…"
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    self.permission = AVCaptureDevice.authorizationStatus(for: .video)
                    ok ? self.begin() : (self.status = "Camera access denied — enable it in Settings, then press Start")
                }
            }
        }
    }

    private func begin() {
        configureIfNeeded()
        guard session.inputs.isEmpty == false else { return }
        queue.async { self.session.startRunning() }
        isRunning = true
        recenter()
    }

    func stop() {
        queue.async { self.session.stopRunning() }
        isRunning = false
        controlsCursor = false
        faceDetected = false
        debug = nil
        status = "Idle"
    }

    /// Look at the centre of the screen, then call this: it defines "straight ahead".
    func recenter() {
        lastOpenSignal = nil
        recenterAccum = (0, 0)
        recenterFrames = 30
        status = "Look at the centre of the screen…"
    }

    private func configureIfNeeded() {
        guard session.inputs.isEmpty else { return }
        guard let device = Self.camera() else {
            status = "No camera found"
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            status = "Camera \(device.localizedName) could not be opened — is another app using it?"
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    // MARK: - Frames

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sb) else { return }
        let w = Double(CVPixelBufferGetWidth(pixels)), h = Double(CVPixelBufferGetHeight(pixels))

        // Landmarks alone leave yaw/pitch nil; only the rectangles request (revision 3)
        // fills in head pose, so run both over the same frame.
        let landmarks = VNDetectFaceLandmarksRequest()
        let rectangles = VNDetectFaceRectanglesRequest()
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([landmarks, rectangles])
        let pose = (rectangles.results ?? []).first

        guard let face = (landmarks.results ?? []).first,
              let d = describe(face, pose: pose, aspect: h > 0 ? w / h : 1) else {
            DispatchQueue.main.async {
                self.faceDetected = false
                self.debug = nil
                if self.videoAspect != w / h, h > 0 { self.videoAspect = w / h }
            }
            return
        }
        DispatchQueue.main.async {
            if h > 0 { self.videoAspect = w / h }
            self.debug = d
            self.consume(d)
        }
    }

    /// Pull face box, eye outlines and pupils into image-normalized space.
    private func describe(_ face: VNFaceObservation, pose: VNFaceObservation?, aspect: Double) -> FaceDebug? {
        guard let lm = face.landmarks else { return nil }
        let box = face.boundingBox

        // Landmarks are normalized inside the face box; lift them into image space.
        func lift(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (region?.normalizedPoints ?? []).map {
                CGPoint(x: box.minX + CGFloat($0.x) * box.width,
                        y: box.minY + CGFloat($0.y) * box.height)
            }
        }
        func offset(_ pupil: [CGPoint], _ eye: [CGPoint]) -> CGPoint? {
            guard let p = pupil.first else { return nil }
            guard let r = GazeMath.cornerRelative(pupil: (Double(p.x), Double(p.y)),
                                                  eye: eye.map { (Double($0.x), Double($0.y)) },
                                                  aspect: aspect) else { return nil }
            return CGPoint(x: r.x, y: r.y)
        }

        var d = FaceDebug()
        d.box = box
        d.leftEye = lift(lm.leftEye)
        d.rightEye = lift(lm.rightEye)
        d.leftPupil = lift(lm.leftPupil).first
        d.rightPupil = lift(lm.rightPupil).first
        d.leftOffset = offset(lift(lm.leftPupil), d.leftEye)
        d.rightOffset = offset(lift(lm.rightPupil), d.rightEye)
        let ears = [d.leftEye, d.rightEye].compactMap {
            GazeMath.eyeAspectRatio(eye: $0.map { (Double($0.x), Double($0.y)) }, aspect: aspect)
        }
        d.openness = ears.isEmpty ? nil : ears.reduce(0, +) / Double(ears.count)
        d.yaw = (pose ?? face).yaw?.doubleValue ?? 0
        d.pitch = (pose ?? face).pitch?.doubleValue ?? 0
        guard d.leftOffset != nil || d.rightOffset != nil else { return nil }
        return d
    }

    private func consume(_ d: FaceDebug) {
        faceDetected = true
        let offsets = [d.leftOffset, d.rightOffset].compactMap { $0 }
        let px = offsets.map { Double($0.x) }.reduce(0, +) / Double(offsets.count)
        let py = offsets.map { Double($0.y) }.reduce(0, +) / Double(offsets.count)
        // Eyes steer near the centre; head turn carries the cursor the rest of the way.
        let yaw = GazeMath.deadzone(d.yaw, threshold: headDeadzone)
        let pitch = GazeMath.deadzone(d.pitch, threshold: headDeadzone)
        let signal = (x: px * gainX + yaw * yawGain, y: py * gainY + pitch * pitchGain)

        if handleBlink(d, signal: signal) { return }   // eyes shut: pupils mean nothing

        if recenterFrames > 0 {
            recenterAccum.x += signal.x
            recenterAccum.y += signal.y
            recenterFrames -= 1
            if recenterFrames == 0 {
                centerX = recenterAccum.x / 30
                centerY = recenterAccum.y / 30
                rawX = 0.5; rawY = 0.5
                status = isRunning ? "Tracking" : "Idle"
            }
            return
        }

        // gains are already folded into the signal, so map with gain 1
        rawX = GazeMath.ema(rawX, GazeMath.map(raw: signal.x, center: centerX, gain: 1), alpha: smoothing)
        rawY = GazeMath.ema(rawY, GazeMath.map(raw: signal.y, center: centerY, gain: 1), alpha: smoothing)
        gaze = CGPoint(x: rawX, y: 1 - rawY)  // Vision origin is bottom-left, screens are top-left
        if controlsCursor { moveCursor(to: gaze) }
    }

    /// Returns true while the eyes are shut. On the blink itself, snap the baseline to the
    /// last open-eyed sample so the dot returns to the middle of the screen.
    private func handleBlink(_ d: FaceDebug, signal: (x: Double, y: Double)) -> Bool {
        guard let openness = d.openness else { return false }
        let shut = openness < blinkThreshold
        blinking = shut

        guard shut else {
            closedFrames = 0
            blinkArmed = true
            lastOpenSignal = signal
            return false
        }

        closedFrames += 1
        if closedFrames == 2, blinkArmed, blinkRecenters, recenterFrames == 0, let pre = lastOpenSignal {
            blinkArmed = false          // one recenter per blink, not one per closed frame
            blinkCount += 1
            centerX = pre.x
            centerY = pre.y
            rawX = 0.5; rawY = 0.5
            gaze = CGPoint(x: 0.5, y: 0.5)
        }
        return true
    }

    // MARK: - Cursor

    private func moveCursor(to g: CGPoint) {
        if Date() < yieldUntil { return }
        guard let frame = NSScreen.main?.frame else { return }
        let current = NSEvent.mouseLocation
        let flipped = CGPoint(x: current.x, y: frame.height - current.y)
        if lastWarp != .zero, hypot(flipped.x - lastWarp.x, flipped.y - lastWarp.y) > 60 {
            yieldUntil = Date().addingTimeInterval(3)   // human grabbed the mouse
            return
        }
        let p = CGPoint(x: frame.width * g.x, y: frame.height * g.y)
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
        lastWarp = p
    }
}
