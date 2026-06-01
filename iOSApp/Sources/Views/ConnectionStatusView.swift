import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.connectionState.color)
                .frame(width: 8, height: 8)
                .animation(.easeInOut, value: appState.connectionState)

            Text(appState.connectionState.displayText)
                .font(.caption)
                .foregroundColor(.secondary)

            if !appState.connectedMacName.isEmpty && appState.connectionState.isConnected {
                Text("·")
                    .foregroundColor(.secondary)
                Text(appState.connectedMacName)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }

            Spacer()

            if appState.connectionState.isConnected {
                Button {
                    appState.disconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}
