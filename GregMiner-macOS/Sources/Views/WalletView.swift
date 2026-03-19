import SwiftUI

struct WalletView: View {
    @EnvironmentObject var appState: AppState
    @State private var copiedAddress = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Wallet")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button {
                        appState.refreshWallet()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appState.isConnected)
                }

                if appState.nodeStatus == .starting {
                    startingView
                } else if !appState.isConnected {
                    notConnectedView
                } else {
                    // Balance
                    GroupBox {
                        VStack(spacing: 16) {
                            VStack(spacing: 4) {
                                Text("Total Balance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(appState.balance + appState.unconfirmedBalance, specifier: "%.8f") GRC")
                                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green)
                            }

                            Divider()

                            HStack(spacing: 40) {
                                VStack(spacing: 2) {
                                    Text("Confirmed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(appState.balance, specifier: "%.8f") GRC")
                                        .font(.title3.monospacedDigit())
                                }
                                VStack(spacing: 2) {
                                    Text("Unconfirmed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(appState.unconfirmedBalance, specifier: "%.8f") GRC")
                                        .font(.title3.monospacedDigit())
                                        .foregroundStyle(appState.unconfirmedBalance > 0 ? .yellow : .secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                    }

                    // Receive
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Receive GRC", systemImage: "arrow.down.circle")
                                .font(.headline)

                            HStack {
                                Text(appState.currentAddress.isEmpty ? "No address" : appState.currentAddress)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(appState.currentAddress, forType: .string)
                                    copiedAddress = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copiedAddress = false
                                    }
                                } label: {
                                    Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .disabled(appState.currentAddress.isEmpty)

                                Button {
                                    appState.generateNewAddress()
                                } label: {
                                    Label("New Address", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                            }

                            if copiedAddress {
                                Text("Address copied to clipboard!")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }

                            Text("Share this address to receive GRC. Click the copy button to copy it to your clipboard.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }

                    // Transaction history
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Transaction History", systemImage: "list.bullet.rectangle")
                                .font(.headline)

                            if appState.transactions.isEmpty {
                                Text("No transactions yet")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(20)
                            } else {
                                ForEach(appState.transactions) { tx in
                                    TransactionDetailRow(tx: tx)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
    }

    private var startingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Starting Gregcoin node...")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("This may take a moment on first launch.")
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
            Text("Connect to a Gregcoin node to use the wallet.")
                .foregroundStyle(.secondary)
            Button("Go to Settings") {
                appState.selectedTab = .node
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

struct TransactionDetailRow: View {
    let tx: WalletTransaction

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: tx.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(tx.amount >= 0 ? .green : .red)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tx.category.capitalized)
                            .font(.body.bold())
                        Spacer()
                        Text("\(tx.amount >= 0 ? "+" : "")\(tx.amount, specifier: "%.8f") GRC")
                            .font(.body.monospacedDigit().bold())
                            .foregroundStyle(tx.amount >= 0 ? .green : .red)
                    }

                    HStack {
                        if let addr = tx.address {
                            Text(addr)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text("\(tx.confirmations) conf")
                            .font(.caption)
                            .foregroundStyle(tx.confirmations >= 6 ? .green : .orange)
                    }

                    HStack {
                        Text(tx.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(tx.txid.prefix(16) + "...")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.vertical, 8)
            Divider()
        }
    }
}
