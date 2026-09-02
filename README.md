# EyeTracker

A native macOS app that uses the built-in webcam to estimate gaze direction and control the mouse cursor. **All processing is local** — no frames leave your Mac.

## Status

Working end to end: camera capture, face/eye/pupil detection, gaze estimation, cursor control.
Calibration is still manual (sliders); a fitted calibration routine is the next step.

The window shows a live camera preview with the detected face box, both eye outlines,
pupil dots and a per-eye arrow showing which way the pupil sits off centre — plus the raw
numbers the gaze estimate is built from.

### How the gaze signal works

- **Horizontal / vertical** — pupil offset from the line between the two eye corners,
  measured in eye widths. Corners are used rather than the eyelid outline because the
  eyelid closes over the pupil when you look down, which hides vertical gaze almost entirely.
- **Head assist** — head yaw and pitch are added on top, past a deadzone. The eyes have
  limited travel; turning your head carries the cursor the rest of the way to the screen edge.
- **Smoothing** — exponential moving average over the estimate.
- **Blink to re-center** — a blink (eye openness below threshold for two frames) snaps the
  baseline back to centre, using the last sample from before the eyes shut.

### Safety

Cursor control pauses for 3 seconds whenever the real mouse is moved by hand, so the app
never fights you for the pointer.

## Requirements

- macOS 14.0+
- Xcode 16+ (Xcode 26 used during development)
- A built-in, external or Continuity camera
- Camera permission

## Build & Run

```bash
cd EyeTracker
xcodegen generate
xcodebuild -project EyeTracker.xcodeproj -scheme EyeTracker -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/EyeTracker-*/Build/Products/Debug/EyeTracker.app
```

Or open `EyeTracker.xcodeproj` in Xcode and press **Cmd+R**.

## Project layout

```
EyeTracker/
├── App/             App entry point + Info.plist + entitlements
├── Tracker/         GazeTracker (capture + Vision + cursor), GazeMath (pure math)
├── Cursor/          CursorController (CGEvent)
└── UI/              ContentView (preview, overlay, tuning)
```

## Privacy

No frames are uploaded, saved to disk, or transmitted. Camera access is requested only when the user starts tracking.

## Limitations

This is an approximate gaze tracker, not medical-grade. Accuracy depends on lighting, head stability, and webcam quality.

## Tests

The gaze math is pure and has a self-check with no test framework:

```bash
swiftc -o /tmp/gazecheck Sources/Tracker/GazeMath.swift Tests/main.swift && /tmp/gazecheck
```
