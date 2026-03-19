import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            nodeSettingsTab
                .tabItem {
                    Label("Node", systemImage: "network")
                }

            miningSettingsTab
                .tabItem {
                    Label("Mining", systemImage: "hammer")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Node Settings

    private var nodeSettingsTab: some View {
        Form {
            Section("Connection") {
                Picker("Mode", selection: $appState.nodeMode) {
                    ForEach(NodeMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                TextField("RPC Host", text: $appState.rpcHost)
                TextField("RPC Port", value: $appState.rpcPort, format: .number)
                TextField("RPC User", text: $appState.rpcUser)
                SecureField("RPC Password", text: $appState.rpcPassword)
            }

            if appState.nodeMode == .embedded {
                Section("Embedded Node") {
                    HStack {
                        TextField("gregcoind Path", text: $appState.gregcoindPath)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.title = "Select gregcoind"
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let url = panel.url {
                                appState.gregcoindPath = url.path
                            }
                        }
                    }
                    Text("Data directory: \(GregcoinParams.defaultDataDir.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Info") {
                Text("The built-in node starts automatically when the app launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Mining Settings

    private var miningSettingsTab: some View {
        Form {
            Section("Mining Address") {
                TextField("Address (leave blank to auto-generate)", text: $appState.miningAddress)
                    .font(.system(.body, design: .monospaced))
                Text("Block rewards will be sent to this address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("GregMiner")
                .font(.title.bold())
            Text("Gregcoin (GRC) Wallet, Node & Miner")
                .foregroundStyle(.secondary)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Ticker:").foregroundStyle(.secondary)
                    Text("GRC")
                }
                GridRow {
                    Text("Supply:").foregroundStyle(.secondary)
                    Text("42,000,000 GRC")
                }
                GridRow {
                    Text("Block Reward:").foregroundStyle(.secondary)
                    Text("100 GRC")
                }
                GridRow {
                    Text("Block Time:").foregroundStyle(.secondary)
                    Text("2.5 minutes")
                }
                GridRow {
                    Text("Halving:").foregroundStyle(.secondary)
                    Text("Every 210,000 blocks")
                }
            }
            .font(.body.monospaced())

            Divider()

            Text("A fun project. Not financial advice. Mine responsibly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(24)
    }
}
