import SwiftUI

/// First-run screen shown when gregcoind isn't bundled or configured
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var customPath = ""
    @State private var showAdvanced = false
    @State private var searchStatus = ""

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

                Text("GregMiner needs the **gregcoind** binary to run a Gregcoin node.\nLocate it on your Mac to get started.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 450)

                // Main actions
                HStack(spacing: 12) {
                    Button {
                        appState.locateGregcoind()
                    } label: {
                        Label("Browse for gregcoind...", systemImage: "folder")
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)

                    Button {
                        autoDetect()
                    } label: {
                        Label("Auto-Detect", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if !searchStatus.isEmpty {
                    Text(searchStatus)
                        .font(.caption)
                        .foregroundStyle(searchStatus.starts(with: "Found") ? .green : .orange)
                        .multilineTextAlignment(.center)
                }

                // Advanced toggle
                DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Manual path entry
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Or paste the full path:")
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
                            Text("Already running a node on another machine?")
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
                    Text("Don't have gregcoind yet?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Build from source: **github.com/chartractegg/gregcoin**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Or just download the release DMG — it comes bundled.")
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
        .onAppear {
            // Try auto-detect on appear
            if let path = NodeManager.bundledBinaryPath {
                searchStatus = "Found: \(path)"
                appState.completeSetup(path: path)
            }
        }
    }

    private func autoDetect() {
        searchStatus = "Searching..."
        // Run on background to not block UI
        DispatchQueue.global().async {
            // Search common locations
            let searchPaths = [
                "/usr/local/bin/gregcoind",
                "/opt/homebrew/bin/gregcoind",
                "/tmp/gregcoin-build/build/bin/gregcoind",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/gregcoin/build/bin/gregcoind",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/Developer/GregMiner/Resources/gregcoind",
            ]

            // Also try `which` and `mdfind`
            var found: String? = nil

            for path in searchPaths {
                if FileManager.default.isExecutableFile(atPath: path) {
                    found = path
                    break
                }
            }

            // Try `which gregcoind`
            if found == nil {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                task.arguments = ["gregcoind"]
                let pipe = Pipe()
                task.standardOutput = pipe
                try? task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    found = path
                }
            }

            // Try mdfind
            if found == nil {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
                task.arguments = ["-name", "gregcoind"]
                let pipe = Pipe()
                task.standardOutput = pipe
                try? task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let results = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                for result in results {
                    let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    if path.hasSuffix("gregcoind") && FileManager.default.isExecutableFile(atPath: path) {
                        found = path
                        break
                    }
                }
            }

            DispatchQueue.main.async {
                if let path = found {
                    searchStatus = "Found: \(path)"
                    appState.completeSetup(path: path)
                } else {
                    searchStatus = "Not found. Use Browse to locate it manually."
                }
            }
        }
    }
}
