import SwiftUI

struct LaunchStatusView: View {
    let status: ConnectionStatus
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ConnectionStatusIndicator(status: status, size: .large)

            switch status {
            case .connecting:
                Text("Connecting to Firebase…")
                    .font(.body)
                    .foregroundColor(.secondary)
            case .connected:
                Text("Connected")
                    .font(.body)
                    .foregroundColor(.secondary)
            case .error(let message):
                VStack(spacing: 8) {
                    Text("Connection Error")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if case .error = status {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    VStack(spacing: 20) {
        LaunchStatusView(status: .connecting, onRetry: {})
        LaunchStatusView(status: .connected, onRetry: {})
        LaunchStatusView(status: .error("The Internet connection appears to be offline."), onRetry: {})
    }
}
