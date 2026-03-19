import SwiftUI

@main
struct GregMinerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Node") {
                Button("Start Node") { appState.startNode() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(appState.nodeStatus == .running)
                Button("Stop Node") { appState.stopNode() }
                    .keyboardShortcut("n", modifiers: [.command, .shift, .option])
                    .disabled(appState.nodeStatus != .running)
                Divider()
                Button("Open Data Directory...") { appState.openDataDirectory() }
            }
            CommandMenu("Mining") {
                Button(appState.isMining ? "Stop Mining" : "Start Mining") {
                    if appState.isMining { appState.stopMining() }
                    else { appState.startMining() }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
