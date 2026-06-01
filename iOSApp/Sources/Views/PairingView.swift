import SwiftUI

struct PairingView: View {
    @EnvironmentObject var appState: AppState
    @State private var pin = ""
    @State private var isSubmitting = false
    @FocusState private var pinFocused: Bool

    private let pinLength = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Mac name
                VStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    if !appState.connectedMacName.isEmpty {
                        Text(appState.connectedMacName)
                            .font(.title3.bold())
                    }
                    Text("Enter the 4-digit PIN shown\nin the Mac app's menu bar.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // PIN dots + hidden field
                ZStack {
                    TextField("", text: $pin)
                        .keyboardType(.numberPad)
                        .focused($pinFocused)
                        .opacity(0)
                        .frame(width: 1, height: 1)
                        .onChange(of: pin) { newValue in
                            // Restrict to digits, max length
                            let filtered = String(newValue.filter { $0.isNumber }.prefix(pinLength))
                            if filtered != newValue { pin = filtered }
                            if filtered.count == pinLength { submitPIN() }
                        }

                    HStack(spacing: 16) {
                        ForEach(0..<pinLength, id: \.self) { index in
                            PINDot(filled: index < pin.count)
                        }
                    }
                    .onTapGesture { pinFocused = true }
                }

                if isSubmitting {
                    ProgressView("Verifying…")
                }

                if case .failed(let msg) = appState.connectionState {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.callout)
                }

                Spacer()
            }
            .padding(32)
            .navigationTitle("Pair with Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.isPairingSheetPresented = false
                        appState.disconnect()
                    }
                }
            }
            .onAppear {
                pinFocused = true
            }
        }
    }

    private func submitPIN() {
        isSubmitting = true
        appState.submitPIN(pin)
        // Reset after delay if still in pairing state
        Task {
            try? await Task.sleep(for: .seconds(5))
            if case .pairing = appState.connectionState {
                isSubmitting = false
                pin = ""
            } else {
                isSubmitting = false
            }
        }
    }
}

private struct PINDot: View {
    let filled: Bool

    var body: some View {
        Circle()
            .fill(filled ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 20, height: 20)
            .animation(.spring(response: 0.2), value: filled)
    }
}
