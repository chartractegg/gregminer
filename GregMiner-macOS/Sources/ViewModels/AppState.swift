import SwiftUI
import Combine

/// Central app state shared across all views
class AppState: ObservableObject {
    // Node
    @Published var nodeManager = NodeManager()
    @Published var nodeMode: NodeMode = .embedded {
        didSet { nodeManager.mode = nodeMode }
    }

    // Wallet
    @Published var balance: Double = 0
    @Published var unconfirmedBalance: Double = 0
    @Published var currentAddress: String = ""
    @Published var transactions: [WalletTransaction] = []
    @Published var walletLoaded = false

    // Miner
    @Published var minerEngine = MinerEngine()
    @Published var miningAddress: String = ""

    // UI
    @Published var selectedTab: SidebarTab = .dashboard
    @Published var statusMessage: String = ""

    // Settings (persisted)
    @AppStorage("rpcHost") var rpcHost: String = "127.0.0.1"
    @AppStorage("rpcPort") var rpcPort: Int = Int(GregcoinParams.rpcPort)
    @AppStorage("rpcUser") var rpcUser: String = "grcuser"
    @AppStorage("rpcPassword") var rpcPassword: String = ""
    @AppStorage("gregcoindPath") var gregcoindPath: String = ""
    @AppStorage("nodeMode") var savedNodeMode: String = NodeMode.embedded.rawValue
    @AppStorage("savedMiningAddress") var savedMiningAddress: String = ""

    private var cancellables = Set<AnyCancellable>()
    private var walletPollTimer: Timer?

    var nodeStatus: NodeStatus { nodeManager.status }
    var isMining: Bool { minerEngine.isRunning }
    var isConnected: Bool { nodeManager.status == .running }

    init() {
        // Auto-generate RPC password on first launch
        if rpcPassword.isEmpty {
            rpcPassword = NodeManager.generatePassword()
        }

        // Restore node mode
        nodeMode = NodeMode(rawValue: savedNodeMode) ?? .embedded

        // Sync settings to node manager
        syncSettings()

        // Watch node status changes
        nodeManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        minerEngine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Load saved mining address
        miningAddress = savedMiningAddress

        // Auto-start the built-in node — this is the default experience.
        // The app just works out of the box.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startNode()
        }
    }

    func syncSettings() {
        nodeManager.rpcHost = rpcHost
        nodeManager.rpcPort = UInt16(rpcPort)
        nodeManager.rpcUser = rpcUser
        nodeManager.rpcPassword = rpcPassword
        nodeManager.binaryPath = gregcoindPath
        nodeManager.mode = nodeMode
        savedNodeMode = nodeMode.rawValue
    }

    // MARK: - Node

    func startNode() {
        syncSettings()
        nodeManager.start()

        // Poll for wallet readiness once node is up
        startWalletPolling()
    }

    func stopNode() {
        if isMining { stopMining() }
        walletPollTimer?.invalidate()
        walletPollTimer = nil
        nodeManager.stop()
        walletLoaded = false
    }

    func openDataDirectory() {
        NSWorkspace.shared.open(nodeManager.dataDir)
    }

    /// Keep trying to load the wallet until the node is ready
    private func startWalletPolling() {
        walletPollTimer?.invalidate()
        walletPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.isConnected {
                self.refreshWallet()
                if self.walletLoaded {
                    timer.invalidate()
                    self.walletPollTimer = nil
                }
            }
        }
    }

    // MARK: - Wallet

    func refreshWallet() {
        guard let rpc = nodeManager.getRPCClient() else { return }

        Task { @MainActor in
            do {
                // Ensure wallet exists
                let wallets: [String] = try await rpc.call("listwallets")
                if wallets.isEmpty {
                    let _: Any = try await rpc.callRaw("createwallet", params: ["default"])
                }
                walletLoaded = true

                // Get balance
                let bal: Double = try await rpc.call("getbalance")
                let ubal: Double = try await rpc.call("getunconfirmedbalance")
                self.balance = bal
                self.unconfirmedBalance = ubal

                // Get address if we don't have one
                if currentAddress.isEmpty {
                    let addr: String = try await rpc.call("getnewaddress")
                    self.currentAddress = addr
                }

                // Get transactions
                let txs: [WalletTransaction] = try await rpc.call("listtransactions", params: ["*", 50, 0, true])
                self.transactions = txs.reversed()
            } catch {
                // Don't spam status bar during startup
                if walletLoaded {
                    statusMessage = "Wallet error: \(error.localizedDescription)"
                }
            }
        }
    }

    func generateNewAddress() {
        guard let rpc = nodeManager.getRPCClient() else { return }

        Task { @MainActor in
            do {
                let addr: String = try await rpc.call("getnewaddress")
                self.currentAddress = addr
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    func sendGRC(to address: String, amount: Double, fee: Double) async throws -> String {
        guard let rpc = nodeManager.getRPCClient() else {
            throw RPCError.invalidResponse
        }

        let _: Any = try await rpc.callRaw("settxfee", params: [fee])
        let txid: String = try await rpc.call("sendtoaddress", params: [address, amount])

        await MainActor.run {
            refreshWallet()
        }

        return txid
    }

    // MARK: - Mining

    func startMining() {
        guard let rpc = nodeManager.getRPCClient() else {
            statusMessage = "Node is still starting..."
            return
        }

        var addr = miningAddress
        if addr.isEmpty {
            // Auto-generate from wallet
            Task { @MainActor in
                do {
                    let wallets: [String] = try await rpc.call("listwallets")
                    if wallets.isEmpty {
                        let _: Any = try await rpc.callRaw("createwallet", params: ["default"])
                    }
                    let newAddr: String = try await rpc.call("getnewaddress")
                    self.miningAddress = newAddr
                    self.savedMiningAddress = newAddr
                    self.minerEngine.start(rpc: rpc, address: newAddr)
                } catch {
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
            return
        }

        savedMiningAddress = addr
        minerEngine.start(rpc: rpc, address: addr)
    }

    func stopMining() {
        minerEngine.stop()
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case wallet = "Wallet"
    case send = "Send"
    case miner = "Miner"
    case node = "Node"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .wallet: return "creditcard"
        case .send: return "arrow.up.circle"
        case .miner: return "hammer"
        case .node: return "network"
        }
    }
}
