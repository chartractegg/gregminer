import Foundation
import Combine

enum NodeStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error(String)

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .stopping: return "Stopping..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isHealthy: Bool {
        self == .running
    }
}

enum NodeMode: String, CaseIterable, Identifiable {
    case embedded = "Built-in Node"
    case remote = "Remote Node"

    var id: String { rawValue }
}

/// Manages the lifecycle of an embedded gregcoind process
class NodeManager: ObservableObject {
    @Published var status: NodeStatus = .stopped
    @Published var blockchainInfo: BlockchainInfo?
    @Published var networkInfo: NetworkInfo?
    @Published var peerCount: Int = 0
    @Published var mempoolInfo: MempoolInfo?
    @Published var logLines: [String] = []

    private var process: Process?
    private var rpcClient: RPCClient?
    private var pollTimer: Timer?
    private var logPipe: Pipe?

    // Configuration
    var binaryPath: String = ""
    var dataDir: URL = GregcoinParams.defaultDataDir
    var rpcHost: String = "127.0.0.1"
    var rpcPort: UInt16 = GregcoinParams.rpcPort
    var rpcUser: String = "grcuser"
    var rpcPassword: String = ""

    var mode: NodeMode = .embedded

    var isEmbedded: Bool { mode == .embedded }

    /// Path to the gregcoind binary bundled inside the .app
    static var bundledBinaryPath: String? {
        // Look inside the app bundle: GregMiner.app/Contents/Resources/gregcoind
        if let resourceURL = Bundle.main.resourceURL {
            let path = resourceURL.appendingPathComponent("gregcoind").path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fallback: check next to the executable (for dev/SPM builds)
        if let execURL = Bundle.main.executableURL {
            let path = execURL.deletingLastPathComponent().appendingPathComponent("gregcoind").path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Generate a random RPC password for first-run
    static func generatePassword(length: Int = 32) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    // MARK: - Node Lifecycle

    func start() {
        guard status == .stopped || status.label.starts(with: "Error") else { return }

        if mode == .remote {
            connectRemote()
            return
        }

        startEmbedded()
    }

    func stop() {
        guard status == .running || status == .starting else { return }
        status = .stopping
        pollTimer?.invalidate()
        pollTimer = nil

        if mode == .embedded {
            stopEmbedded()
        } else {
            status = .stopped
            rpcClient = nil
        }
    }

    // MARK: - Embedded Node

    private func startEmbedded() {
        status = .starting

        // Resolve binary path: explicit setting > bundled > error
        let resolvedPath: String
        if !binaryPath.isEmpty && FileManager.default.isExecutableFile(atPath: binaryPath) {
            resolvedPath = binaryPath
        } else if let bundled = NodeManager.bundledBinaryPath {
            resolvedPath = bundled
            addLog("Using bundled gregcoind")
        } else {
            status = .error("gregcoind not found. Go to Settings to set the path.")
            addLog("ERROR: gregcoind binary not found in app bundle or at configured path")
            return
        }

        // Ensure data directory exists
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // Write config if it doesn't exist
        ensureConfig()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = [
            "-datadir=\(dataDir.path)",
            "-server=1",
            "-rpcuser=\(rpcUser)",
            "-rpcpassword=\(rpcPassword)",
            "-rpcport=\(rpcPort)",
            "-rpcallowip=127.0.0.1",
            "-printtoconsole",
        ]

        // Capture stdout/stderr for log
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.logPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self?.addLog(trimmed)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.pollTimer?.invalidate()
                self?.pollTimer = nil
                if self?.status != .stopping {
                    self?.status = .error("Node exited with code \(proc.terminationStatus)")
                } else {
                    self?.status = .stopped
                }
                self?.process = nil
            }
        }

        do {
            try process.run()
            self.process = process
            addLog("Node started (PID: \(process.processIdentifier))")

            // Wait a bit then start polling RPC
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.setupRPC()
                self?.startPolling()
            }
        } catch {
            status = .error(error.localizedDescription)
            addLog("Failed to start: \(error.localizedDescription)")
        }
    }

    private func stopEmbedded() {
        // Try graceful shutdown via RPC first
        if let rpc = rpcClient {
            Task {
                try? await rpc.callVoid("stop")
            }
        }

        // Give it a few seconds, then force kill
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.terminate()
            }
        }
    }

    // MARK: - Remote Node

    private func connectRemote() {
        status = .starting
        setupRPC()
        startPolling()
    }

    // MARK: - RPC

    private func setupRPC() {
        rpcClient = RPCClient(
            host: rpcHost,
            port: rpcPort,
            user: rpcUser,
            password: rpcPassword
        )
    }

    func getRPCClient() -> RPCClient? {
        return rpcClient
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollNodeStatus()
        }
        pollNodeStatus()
    }

    private func pollNodeStatus() {
        guard let rpc = rpcClient else { return }

        Task { @MainActor in
            do {
                let info: BlockchainInfo = try await rpc.call("getblockchaininfo")
                self.blockchainInfo = info
                self.status = .running

                if let netInfo: NetworkInfo = try? await rpc.call("getnetworkinfo") {
                    self.networkInfo = netInfo
                    self.peerCount = netInfo.connections
                }

                if let memInfo: MempoolInfo = try? await rpc.call("getmempoolinfo") {
                    self.mempoolInfo = memInfo
                }
            } catch {
                if self.status == .starting {
                    // Still waiting for node to be ready
                } else if self.status == .running {
                    self.status = .error("Connection lost")
                }
            }
        }
    }

    // MARK: - Config

    private func ensureConfig() {
        let confPath = dataDir.appendingPathComponent("gregcoin.conf")
        if !FileManager.default.fileExists(atPath: confPath.path) {
            let conf = """
            server=1
            rpcuser=\(rpcUser)
            rpcpassword=\(rpcPassword)
            rpcallowip=127.0.0.1
            rpcport=\(rpcPort)
            """
            try? conf.write(to: confPath, atomically: true, encoding: .utf8)
            addLog("Created gregcoin.conf")
        }
    }

    // MARK: - Logging

    private func addLog(_ line: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        logLines.append("[\(timestamp)] \(line)")
        // Keep last 500 lines
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
