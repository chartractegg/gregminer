import SwiftUI

struct MinerView: View {
    @EnvironmentObject var appState: AppState
    @State private var logMessages: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("CPU Miner")
                        .font(.largeTitle.bold())
                    Spacer()
                    if appState.isMining {
                        Text("MINING")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                }

                if appState.nodeStatus == .starting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Waiting for node to start...")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if !appState.isConnected {
                    notConnectedView
                } else {
                    // Mining address
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Mining Configuration", systemImage: "gearshape")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mining Address")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Leave blank to auto-generate from wallet", text: $appState.miningAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .disabled(appState.isMining)
                                Text("Block rewards will be sent to this address. If empty, a new address will be generated from your wallet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Live stats
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Live Stats", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.headline)

                            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 12) {
                                GridRow {
                                    Text("Hash Rate")
                                        .foregroundStyle(.secondary)
                                    Text(formatHashrate(appState.minerEngine.hashrate))
                                        .font(.title2.bold().monospacedDigit())
                                        .foregroundStyle(appState.isMining ? .green : .secondary)
                                }
                                GridRow {
                                    Text("Blocks Found")
                                        .foregroundStyle(.secondary)
                                    Text("\(appState.minerEngine.blocksFound)")
                                        .font(.title2.bold().monospacedDigit())
                                        .foregroundStyle(appState.minerEngine.blocksFound > 0 ? .green : .primary)
                                }
                                GridRow {
                                    Text("Uptime")
                                        .foregroundStyle(.secondary)
                                    Text(formatUptime(appState.minerEngine.uptime))
                                        .font(.title2.monospacedDigit())
                                }
                                GridRow {
                                    Text("Status")
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(appState.isMining ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        Text(appState.isMining ? "Mining" : "Stopped")
                                            .font(.body.bold())
                                            .foregroundStyle(appState.isMining ? .green : .red)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Controls
                    HStack(spacing: 12) {
                        if !appState.isMining {
                            Button {
                                appState.startMining()
                            } label: {
                                Label("Start Mining", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.large)
                        } else {
                            Button {
                                appState.stopMining()
                            } label: {
                                Label("Stop Mining", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)
                        }
                    }

                    // Error display
                    if let error = appState.minerEngine.lastError {
                        GroupBox {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(4)
                        }
                    }

                    // Mining log
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Mining Log", systemImage: "terminal")
                                .font(.headline)

                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(logMessages.suffix(50), id: \.self) { line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(height: 150)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            appState.minerEngine.onLog = { [self] msg in
                let ts = DateFormatter.logFormatter.string(from: Date())
                logMessages.append("[\(ts)] \(msg)")
                if logMessages.count > 200 {
                    logMessages.removeFirst(logMessages.count - 200)
                }
            }
        }
    }

    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Not Connected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Connect to a Gregcoin node to start mining.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

private func formatUptime(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return String(format: "%02d:%02d:%02d", h, m, s)
}
