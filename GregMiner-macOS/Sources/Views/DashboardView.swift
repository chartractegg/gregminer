import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.largeTitle.bold())
                        Text("Gregcoin wallet, node & miner overview")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                // Balance card
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Wallet Balance", systemImage: "creditcard")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if appState.isConnected && appState.walletLoaded {
                            Text("\(appState.balance + appState.unconfirmedBalance, specifier: "%.8f") GRC")
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)

                            HStack(spacing: 24) {
                                VStack(alignment: .leading) {
                                    Text("Confirmed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(appState.balance, specifier: "%.8f") GRC")
                                        .font(.body.monospacedDigit())
                                }
                                VStack(alignment: .leading) {
                                    Text("Unconfirmed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(appState.unconfirmedBalance, specifier: "%.8f") GRC")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(appState.unconfirmedBalance > 0 ? .yellow : .secondary)
                                }
                            }
                        } else if appState.nodeStatus == .starting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Starting node...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Not connected")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                // Status cards row
                HStack(spacing: 16) {
                    // Node status
                    StatusCard(
                        title: "Node",
                        icon: "network",
                        value: appState.nodeManager.status.label,
                        detail: nodeDetail,
                        color: appState.isConnected ? .green : .gray
                    )

                    // Mining status
                    StatusCard(
                        title: "Miner",
                        icon: "hammer",
                        value: appState.isMining ? "Mining" : "Idle",
                        detail: minerDetail,
                        color: appState.isMining ? .green : .gray
                    )

                    // Network
                    StatusCard(
                        title: "Network",
                        icon: "antenna.radiowaves.left.and.right",
                        value: "\(appState.nodeManager.peerCount) peers",
                        detail: networkDetail,
                        color: appState.nodeManager.peerCount > 0 ? .blue : .gray
                    )
                }

                // Quick actions
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Quick Actions", systemImage: "bolt")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if appState.nodeStatus == .starting {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Node is starting up...")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            } else if !appState.isConnected {
                                Button {
                                    appState.startNode()
                                } label: {
                                    Label("Start Node", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            } else {
                                Button {
                                    appState.refreshWallet()
                                } label: {
                                    Label("Refresh Wallet", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                if !appState.isMining {
                                    Button {
                                        appState.startMining()
                                    } label: {
                                        Label("Start Mining", systemImage: "hammer.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                } else {
                                    Button {
                                        appState.stopMining()
                                    } label: {
                                        Label("Stop Mining", systemImage: "stop.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                // Recent transactions
                if !appState.transactions.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recent Transactions", systemImage: "list.bullet")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            ForEach(appState.transactions.prefix(5)) { tx in
                                TransactionRow(tx: tx)
                            }
                        }
                        .padding(8)
                    }
                }

                // Gregcoin info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gregcoin Parameters", systemImage: "info.circle")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                            ParamRow(key: "Ticker", value: GregcoinParams.ticker)
                            ParamRow(key: "Total Supply", value: "42,000,000 GRC")
                            ParamRow(key: "Block Reward", value: "100 GRC (halves every 210k blocks)")
                            ParamRow(key: "Block Time", value: "2.5 minutes")
                            ParamRow(key: "Address Prefix", value: "G")
                            ParamRow(key: "Mainnet Port", value: "\(GregcoinParams.mainnetPort)")
                            ParamRow(key: "RPC Port", value: "\(GregcoinParams.rpcPort)")
                        }
                    }
                    .padding(8)
                }
            }
            .padding(24)
        }
    }

    private var nodeDetail: String {
        if let info = appState.nodeManager.blockchainInfo {
            return "Height: \(info.blocks) | Difficulty: \(String(format: "%.4f", info.difficulty))"
        }
        return "Not connected"
    }

    private var minerDetail: String {
        if appState.isMining {
            return formatHashrate(appState.minerEngine.hashrate) + " | \(appState.minerEngine.blocksFound) blocks"
        }
        return "Not running"
    }

    private var networkDetail: String {
        if let net = appState.nodeManager.networkInfo {
            return "v\(net.version) \(net.subversion)"
        }
        return "—"
    }
}

struct StatusCard: View {
    let title: String
    let icon: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

struct ParamRow: View {
    let key: String
    let value: String

    var body: some View {
        GridRow {
            Text(key)
                .foregroundStyle(.secondary)
                .font(.body)
            Text(value)
                .font(.body.monospaced())
        }
    }
}

struct TransactionRow: View {
    let tx: WalletTransaction

    var body: some View {
        HStack {
            Image(systemName: tx.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(tx.amount >= 0 ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.category.capitalized)
                    .font(.body)
                if let addr = tx.address {
                    Text(addr)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tx.amount >= 0 ? "+" : "")\(tx.amount, specifier: "%.8f") GRC")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(tx.amount >= 0 ? .green : .red)
                Text(tx.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        Divider()
    }
}

func formatHashrate(_ rate: Double) -> String {
    if rate >= 1_000_000 {
        return String(format: "%.2f MH/s", rate / 1_000_000)
    } else if rate >= 1_000 {
        return String(format: "%.1f KH/s", rate / 1_000)
    } else {
        return String(format: "%.0f H/s", rate)
    }
}
