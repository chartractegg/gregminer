import SwiftUI

struct NodeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("Node")
                        .font(.largeTitle.bold())
                    Spacer()
                    nodeStatusBadge
                }

                // Connection mode
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Connection Mode", systemImage: "network")
                            .font(.headline)

                        Picker("Mode", selection: $appState.nodeMode) {
                            ForEach(NodeMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(appState.isConnected)

                        if appState.nodeMode == .embedded {
                            embeddedConfig
                        } else {
                            remoteConfig
                        }
                    }
                    .padding(8)
                }

                // Connect/disconnect
                HStack(spacing: 12) {
                    if !appState.isConnected && appState.nodeStatus != .starting {
                        Button {
                            appState.startNode()
                        } label: {
                            Label(appState.nodeMode == .embedded ? "Start Node" : "Connect",
                                  systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.large)
                    } else if appState.nodeStatus == .starting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting...")
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Button {
                            appState.stopNode()
                        } label: {
                            Label(appState.nodeMode == .embedded ? "Stop Node" : "Disconnect",
                                  systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                    }
                }

                // Blockchain info
                if appState.isConnected {
                    if let info = appState.nodeManager.blockchainInfo {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Blockchain", systemImage: "cube.transparent")
                                    .font(.headline)

                                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                    GridRow {
                                        Text("Chain").foregroundStyle(.secondary)
                                        Text(info.chain).font(.body.monospaced())
                                    }
                                    GridRow {
                                        Text("Height").foregroundStyle(.secondary)
                                        Text("\(info.blocks)").font(.body.monospacedDigit())
                                    }
                                    GridRow {
                                        Text("Headers").foregroundStyle(.secondary)
                                        Text("\(info.headers)").font(.body.monospacedDigit())
                                    }
                                    GridRow {
                                        Text("Difficulty").foregroundStyle(.secondary)
                                        Text(String(format: "%.6f", info.difficulty)).font(.body.monospacedDigit())
                                    }
                                    GridRow {
                                        Text("Best Block").foregroundStyle(.secondary)
                                        Text(info.bestblockhash.prefix(24) + "...")
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                    if let progress = info.verificationprogress {
                                        GridRow {
                                            Text("Sync Progress").foregroundStyle(.secondary)
                                            Text(String(format: "%.2f%%", progress * 100)).font(.body.monospacedDigit())
                                        }
                                    }
                                    if let ibd = info.initialblockdownload, ibd {
                                        GridRow {
                                            Text("Status").foregroundStyle(.secondary)
                                            Text("Initial Block Download")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }

                    // Network info
                    if let net = appState.nodeManager.networkInfo {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Network", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.headline)

                                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                    GridRow {
                                        Text("Version").foregroundStyle(.secondary)
                                        Text("\(net.version) \(net.subversion)").font(.body.monospaced())
                                    }
                                    GridRow {
                                        Text("Protocol").foregroundStyle(.secondary)
                                        Text("\(net.protocolversion)").font(.body.monospacedDigit())
                                    }
                                    GridRow {
                                        Text("Connections").foregroundStyle(.secondary)
                                        Text("\(net.connections)").font(.body.monospacedDigit())
                                    }
                                    if let inConn = net.connections_in, let outConn = net.connections_out {
                                        GridRow {
                                            Text("In / Out").foregroundStyle(.secondary)
                                            Text("\(inConn) in / \(outConn) out").font(.body.monospacedDigit())
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }

                    // Mempool
                    if let mem = appState.nodeManager.mempoolInfo {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Mempool", systemImage: "tray.full")
                                    .font(.headline)
                                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                    GridRow {
                                        Text("Transactions").foregroundStyle(.secondary)
                                        Text("\(mem.size)").font(.body.monospacedDigit())
                                    }
                                    if let bytes = mem.bytes {
                                        GridRow {
                                            Text("Size").foregroundStyle(.secondary)
                                            Text(formatBytes(bytes)).font(.body.monospacedDigit())
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                }

                // Node log (embedded only)
                if appState.nodeMode == .embedded && !appState.nodeManager.logLines.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Node Log", systemImage: "terminal")
                                .font(.headline)

                            ScrollView {
                                VStack(alignment: .leading, spacing: 1) {
                                    ForEach(appState.nodeManager.logLines.suffix(100), id: \.self) { line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(height: 200)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Subviews

    private var nodeStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(appState.nodeManager.status.label)
                .font(.body)
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch appState.nodeManager.status {
        case .running: return .green
        case .starting: return .yellow
        case .error: return .red
        default: return .gray
        }
    }

    private var embeddedConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The embedded node runs gregcoind as a subprocess managed by this app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("gregcoind Binary Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("/path/to/gregcoind", text: $appState.gregcoindPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Browse...") {
                        browseForBinary()
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Data Directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.nodeManager.dataDir.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            rpcFields
        }
    }

    private var remoteConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect to an existing gregcoind node running on your network.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Host")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("127.0.0.1", text: $appState.rpcHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            rpcFields
        }
    }

    private var rpcFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RPC Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("8445", value: $appState.rpcPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 100)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("RPC User")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("grcuser", text: $appState.rpcUser)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("RPC Password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("password", text: $appState.rpcPassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private func browseForBinary() {
        let panel = NSOpenPanel()
        panel.title = "Select gregcoind binary"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            appState.gregcoindPath = url.path
        }
    }
}

private func formatBytes(_ bytes: Int) -> String {
    if bytes >= 1_048_576 {
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    } else if bytes >= 1024 {
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }
    return "\(bytes) B"
}
