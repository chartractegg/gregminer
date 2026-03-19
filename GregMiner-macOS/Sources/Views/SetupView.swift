import SwiftUI

/// First-run screen shown when gregcoind isn't bundled or configured
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var customPath = ""
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon + title
                Image(systemName: "hammer.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                Text("Welcome to GregMiner")
                    .font(.largeTitle.bold())

                Text("GregMiner needs the Gregcoin node software to run.\nLocate your **gregcoind** binary to get started.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 450)

                // Main action
                Button {
                    appState.locateGregcoind()
                } label: {
                    Label("Locate gregcoind...", systemImage: "folder")
                        .frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

                // Advanced toggle
                DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Manual path entry
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Or enter the path manually:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("/path/to/gregcoind", text: $customPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                Button("Use") {
                                    if !customPath.isEmpty {
                                        appState.completeSetup(path: customPath)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(customPath.isEmpty)
                            }
                        }

                        Divider()

                        // Connect to remote node instead
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Already running a node elsewhere?")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                appState.nodeMode = .remote
                                appState.needsSetup = false
                                appState.selectedTab = .node
                            } label: {
                                Label("Connect to Remote Node", systemImage: "network")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 450)

                // Help text
                VStack(spacing: 4) {
                    Text("Don't have gregcoind?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Build it from source: **github.com/chartractegg/gregcoin**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(40)

            Spacer()

            // Footer
            Text("GregMiner v2.0.0 — Gregcoin (GRC)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
