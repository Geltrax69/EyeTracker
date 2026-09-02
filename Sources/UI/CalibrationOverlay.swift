import SwiftUI
import AppKit

/// Full-screen target for calibration. It has to cover the whole screen — targets crammed
/// into a small window would only span a few degrees of eye movement and fit nothing useful.
final class CalibrationOverlay {
    private var window: NSWindow?

    func show(tracker: GazeTracker) {
        guard window == nil, let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                         backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .black.withAlphaComponent(0.92)
        w.ignoresMouseEvents = true
        w.contentView = NSHostingView(rootView: CalibrationTargets(tracker: tracker))
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

struct CalibrationTargets: View {
    @ObservedObject var tracker: GazeTracker

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(tracker.calibrationTargets.enumerated()), id: \.offset) { i, t in
                    Circle()
                        .fill(i == tracker.calibrationStep ? Color.yellow : Color.white.opacity(0.12))
                        .frame(width: i == tracker.calibrationStep ? 26 : 12)
                        .position(x: geo.size.width * t.x, y: geo.size.height * t.y)
                        .animation(.easeOut(duration: 0.15), value: tracker.calibrationStep)
                }
                VStack(spacing: 6) {
                    Text(tracker.status).font(.title2)
                    Text("Keep your head still-ish and move your eyes to the yellow dot.")
                        .foregroundStyle(.secondary)
                    Text("Press Stop in the main window to cancel.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .position(x: geo.size.width / 2, y: geo.size.height * 0.68)
            }
        }
        .background(.clear)
    }
}
