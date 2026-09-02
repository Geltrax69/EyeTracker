import SwiftUI

/// Calibration UI - placeholder for Milestone 1.
/// Full 9-point calibration will be implemented in Milestone 5.
struct CalibrationView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("Calibration")
                .font(.title)
                .fontWeight(.bold)

            Text("Calibration will be implemented in Milestone 5.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Image(systemName: "scope")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}

#Preview {
    CalibrationView(isPresented: .constant(true))
}
