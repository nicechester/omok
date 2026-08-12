import SwiftUI

struct ConnectionStatusIndicator: View {
    enum Size {
        case small
        case large
    }

    let status: ConnectionStatus
    let size: Size

    private var icon: String {
        switch status {
        case .connecting: return "circle"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .connecting: return .gray
        case .connected: return .green
        case .error: return .red
        }
    }

    private var frameSize: CGFloat {
        size == .small ? 16 : 32
    }

    var body: some View {
        if status == .connecting {
            ProgressView()
                .frame(width: frameSize, height: frameSize)
                .tint(color)
        } else {
            Image(systemName: icon)
                .font(.system(size: size == .small ? 14 : 24))
                .foregroundColor(color)
                .frame(width: frameSize, height: frameSize)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ConnectionStatusIndicator(status: .connecting, size: .large)
        ConnectionStatusIndicator(status: .connected, size: .large)
        ConnectionStatusIndicator(status: .error("Network error"), size: .large)

        HStack(spacing: 20) {
            ConnectionStatusIndicator(status: .connecting, size: .small)
            ConnectionStatusIndicator(status: .connected, size: .small)
            ConnectionStatusIndicator(status: .error("Network error"), size: .small)
        }
    }
    .padding()
}
