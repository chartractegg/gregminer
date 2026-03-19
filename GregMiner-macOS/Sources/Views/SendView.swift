import SwiftUI

struct SendView: View {
    @EnvironmentObject var appState: AppState

    @State private var toAddress = ""
    @State private var amount = ""
    @State private var fee = "0.0001"
    @State private var showConfirmation = false
    @State private var isSending = false
    @State private var resultMessage = ""
    @State private var resultIsError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("Send GRC")
                        .font(.largeTitle.bold())
                    Spacer()
                }

                if appState.nodeStatus == .starting {
                    startingView
                } else if !appState.isConnected {
                    notConnectedView
                } else {
                    // Available balance
                    GroupBox {
                        HStack {
                            Text("Available Balance:")
                                .foregroundStyle(.secondary)
                            Text("\(appState.balance, specifier: "%.8f") GRC")
                                .font(.body.monospacedDigit().bold())
                                .foregroundStyle(.green)
                            Spacer()
                        }
                        .padding(4)
                    }

                    // Send form
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            // To address
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recipient Address")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("G...", text: $toAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            HStack(spacing: 16) {
                                // Amount
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Amount (GRC)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("0.00000000", text: $amount)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }

                                // Fee
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Fee (GRC)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("0.0001", text: $fee)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 150)
                                }
                            }

                            // Send button
                            Button {
                                showConfirmation = true
                            } label: {
                                Label("Send GRC", systemImage: "arrow.up.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.large)
                            .disabled(!isFormValid || isSending)
                        }
                        .padding(8)
                    }

                    // Result
                    if !resultMessage.isEmpty {
                        GroupBox {
                            HStack {
                                Image(systemName: resultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(resultIsError ? .red : .green)
                                Text(resultMessage)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(4)
                        }
                    }

                    // Tips
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Tips", systemImage: "lightbulb")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text("Double-check the recipient address before sending. Transactions cannot be reversed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("The default fee of 0.0001 GRC is typically sufficient for standard transactions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    }
                }
            }
            .padding(24)
        }
        .alert("Confirm Transaction", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Send") {
                performSend()
            }
        } message: {
            Text("Send \(amount) GRC to \(toAddress)\n\nFee: \(fee) GRC\n\nThis cannot be undone.")
        }
    }

    private var isFormValid: Bool {
        !toAddress.isEmpty &&
        Double(amount) != nil &&
        Double(amount)! > 0 &&
        Double(fee) != nil
    }

    private func performSend() {
        guard let amountVal = Double(amount),
              let feeVal = Double(fee) else { return }

        isSending = true
        resultMessage = ""

        Task {
            do {
                let txid = try await appState.sendGRC(to: toAddress, amount: amountVal, fee: feeVal)
                await MainActor.run {
                    resultMessage = "Sent! TXID: \(txid)"
                    resultIsError = false
                    isSending = false
                    // Clear form
                    toAddress = ""
                    amount = ""
                }
            } catch {
                await MainActor.run {
                    resultMessage = error.localizedDescription
                    resultIsError = true
                    isSending = false
                }
            }
        }
    }

    private var startingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Starting Gregcoin node...")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Not Connected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Connect to a Gregcoin node to send GRC.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
