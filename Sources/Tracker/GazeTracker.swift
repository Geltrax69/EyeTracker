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

/// A fitted mapping from eye/head features to screen position. Replaces the tuning
/// sliders: each coefficient's sign and scale is measured, not guessed.
struct Calibration {
    var x: (c0: Double, c1: Double, c2: Double)
    var y: (c0: Double, c1: Double, c2: Double)
    var rms: Double

    func screenPoint(px: Double, py: Double, yaw: Double, pitch: Double) -> CGPoint {
        CGPoint(x: GazeMath.clamp01(x.c0 + x.c1 * px + x.c2 * yaw),
                y: GazeMath.clamp01(y.c0 + y.c1 * py + y.c2 * pitch))
    }
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
    @Published var calibration: Calibration?
    @Published var calibrating = false
    @Published var calibrationTarget = CGPoint(x: 0.5, y: 0.5)
    @Published var calibrationStep = 0
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

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "gaze.frames")
    private var recenterFrames = 0
    private var recenterAccum = (x: 0.0, y: 0.0)

    /// Nine targets across the screen, in normalized top-left-origin coords.
    let calibrationTargets: [CGPoint] = [0.1, 0.5, 0.9].flatMap { y in
        [0.1, 0.5, 0.9].map { CGPoint(x: $0, y: y) }
    }
    private var samplesX: [(f1: Double, f2: Double, target: Double)] = []
    private var samplesY: [(f1: Double, f2: Double, target: Double)] = []
    private var settleUntil = Date.distantPast
    private var samplesHere = 0
    private let samplesPerTarget = 20

    /// Applied after the mapping, so a blink can re-centre a calibrated estimate too.
    private var offset = CGPoint.zero

    /// Blink detection. A blink is a drop below `blinkThreshold` for a couple of frames;
    /// the eyes are shut during it, so recentering uses the last sample from before it.
    let blinkThreshold = 0.17
    private var closedFrames = 0
    private var blinkArmed = true
    private var lastOpenPoint: CGPoint?

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
        calibrating = false
        isRunning = false
        controlsCursor = false
        faceDetected = false
        debug = nil
        status = "Idle"
    }

    /// Look at the centre of the screen, then call this: it defines "straight ahead".
    func recenter() {
        lastOpenPoint = nil
        offset = .zero
        recenterAccum = (0, 0)
        recenterFrames = 30
        status = "Look at the centre of the screen…"
    }

    // MARK: - Calibration

    func startCalibration() {
        guard isRunning else { return }
        samplesX = []; samplesY = []
        calibrationStep = 0
        calibrating = true
        beginTarget()
    }

    func cancelCalibration() {
        calibrating = false
        status = isRunning ? "Tracking" : "Idle"
    }

    func clearCalibration() {
        calibration = nil
        offset = .zero
        status = isRunning ? "Tracking (uncalibrated)" : "Idle"
    }

    private func beginTarget() {
        calibrationTarget = calibrationTargets[calibrationStep]
        samplesHere = 0
        settleUntil = Date().addingTimeInterval(1.0)   // time to actually move your eyes there
        status = "Look at the dot — \(calibrationStep + 1) of \(calibrationTargets.count)"
    }

    /// Returns true while calibration is consuming the frame.
    private func collectCalibration(px: Double, py: Double, yaw: Double, pitch: Double) -> Bool {
        guard calibrating else { return false }
        guard Date() >= settleUntil else { return true }

        let target = calibrationTargets[calibrationStep]
        samplesX.append((f1: px, f2: yaw, target: Double(target.x)))
        samplesY.append((f1: py, f2: pitch, target: Double(target.y)))
        samplesHere += 1
        guard samplesHere >= samplesPerTarget else { return true }

        calibrationStep += 1
        if calibrationStep < calibrationTargets.count {
            beginTarget()
        } else {
            finishCalibration()
        }
        return true
    }

    private func finishCalibration() {
        calibrating = false
        guard let fx = GazeMath.fitPlane(samplesX), let fy = GazeMath.fitPlane(samplesY) else {
            status = "Calibration failed — not enough usable samples, try again"
            return
        }
        let rms = (GazeMath.rmsError(samplesX, fx) + GazeMath.rmsError(samplesY, fy)) / 2
        calibration = Calibration(x: fx, y: fy, rms: rms)
        offset = .zero
        status = String(format: "Calibrated — average error %.0f%% of the screen", rms * 100)
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

        if handleBlink(d, raw: rawPoint(px: px, py: py, yaw: yaw, pitch: pitch)) { return }
        if collectCalibration(px: px, py: py, yaw: yaw, pitch: pitch) { return }

        let raw = rawPoint(px: px, py: py, yaw: yaw, pitch: pitch)

        if recenterFrames > 0 {
            recenterAccum.x += Double(raw.x)
            recenterAccum.y += Double(raw.y)
            recenterFrames -= 1
            if recenterFrames == 0 {
                offset = CGPoint(x: 0.5 - recenterAccum.x / 30, y: 0.5 - recenterAccum.y / 30)
                gaze = CGPoint(x: 0.5, y: 0.5)
                status = isRunning ? (calibration == nil ? "Tracking (uncalibrated)" : "Tracking") : "Idle"
            }
            return
        }

        let target = CGPoint(x: GazeMath.clamp01(Double(raw.x + offset.x)),
                             y: GazeMath.clamp01(Double(raw.y + offset.y)))
        gaze = CGPoint(x: GazeMath.ema(Double(gaze.x), Double(target.x), alpha: smoothing),
                       y: GazeMath.ema(Double(gaze.y), Double(target.y), alpha: smoothing))
        if controlsCursor { moveCursor(to: gaze) }
    }

    /// Screen position before smoothing and blink offset. Uses the fitted calibration when
    /// there is one, and the tuning sliders when there is not.
    /// Vision's y axis points up and the screen's points down, hence the `1 -` in the slider path.
    private func rawPoint(px: Double, py: Double, yaw: Double, pitch: Double) -> CGPoint {
        if let calibration {
            return calibration.screenPoint(px: px, py: py, yaw: yaw, pitch: pitch)
        }
        return CGPoint(x: GazeMath.clamp01(0.5 + px * gainX + yaw * yawGain),
                       y: 1 - GazeMath.clamp01(0.5 + py * gainY + pitch * pitchGain))
    }

    /// Returns true while the eyes are shut. On the blink itself, shift the estimate so the
    /// last open-eyed reading maps to the middle of the screen.
    private func handleBlink(_ d: FaceDebug, raw: CGPoint) -> Bool {
        guard let openness = d.openness else { return false }
        let shut = openness < blinkThreshold
        blinking = shut

        guard shut else {
            closedFrames = 0
            blinkArmed = true
            lastOpenPoint = raw
            return false
        }

        closedFrames += 1
        if closedFrames == 2, blinkArmed, blinkRecenters, !calibrating,
           recenterFrames == 0, let pre = lastOpenPoint {
            blinkArmed = false          // one recenter per blink, not one per closed frame
            blinkCount += 1
            offset = CGPoint(x: offset.x + (0.5 - pre.x), y: offset.y + (0.5 - pre.y))
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
