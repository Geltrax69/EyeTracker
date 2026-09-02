# EyeTracker

A native macOS app that uses the built-in webcam to estimate gaze direction and control the mouse cursor. **All processing is local** — no frames leave your Mac.

## Status

**Milestone 1: Basic macOS application**

The window shows:
- App title and brief description
- Camera status indicator
- Tracking status indicator
- **Start Tracking** / **Stop Tracking** / **Calibrate** buttons
- Privacy notice + emergency-stop hint

Later milestones (camera, Vision, calibration, cursor control, smoothing) will be added incrementally — each will be a separate commit.

## Requirements

- macOS 14.0+
- Xcode 16+ (Xcode 26 used during development)
- A built-in or external webcam (used from Milestone 2)
- Accessibility permission (from Milestone 6, for cursor control)

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
├── Camera/          CameraManager (AVFoundation)
├── Vision/          EyeTracker (Vision framework)
├── Gaze/            CalibrationManager, GazeEstimator, GazeSmoother
├── Cursor/          CursorController (CGEvent)
├── Models/          EyeFeatures, CalibrationPoint
├── UI/              ContentView, CalibrationView
└── Utilities/       PermissionsManager
```

## Privacy

No frames are uploaded, saved to disk, or transmitted. Camera access is requested only when the user starts tracking.

## Limitations

This is an approximate gaze tracker, not medical-grade. Accuracy depends on lighting, head stability, and webcam quality.
