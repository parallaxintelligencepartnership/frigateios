import SwiftUI

/// Main entry point for the Frigate NVR iOS/iPadOS application.
/// Provides a full-featured client for self-hosted Frigate NVR servers.
@main
struct FrigateNVRApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var serverManager = ServerConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(serverManager)
                .onAppear {
                    setupNotifications()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }

    private func setupNotifications() {
        Task {
            await NotificationService.shared.requestAuthorization()
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // Reconnect services when app becomes active
            Task {
                await appState.reconnectServices()
            }
        case .inactive:
            // Prepare for potential backgrounding
            break
        case .background:
            // Maintain MQTT connection for notifications
            appState.enterBackground()
        @unknown default:
            break
        }
    }
}
