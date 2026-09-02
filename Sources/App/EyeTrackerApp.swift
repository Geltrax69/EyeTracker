import SwiftUI

@main
struct EyeTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .help) {
                Link("Eye Tracker Help", destination: URL(string: "https://github.com/Geltrax69/EyeTracker")!)
            }
        }
    }
}
