import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            switch appState.selectedTab {
            case .dashboard:
                DashboardView()
            case .wallet:
                WalletView()
            case .send:
                SendView()
            case .miner:
                MinerView()
            case .node:
                NodeView()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StatusBadge()
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(SidebarTab.allCases, selection: $appState.selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 4) {
                Image(systemName: "hammer.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("GregMiner")
                    .font(.headline)
                Text("Gregcoin (GRC)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                if appState.isConnected {
                    if let info = appState.nodeManager.blockchainInfo {
                        Text("Block \(info.blocks)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if !appState.statusMessage.isEmpty {
                    Text(appState.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct StatusBadge: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var statusText: String {
        if appState.isMining {
            return "Mining - \(appState.nodeManager.status.label)"
        }
        return appState.nodeManager.status.label
    }
}
