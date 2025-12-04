import Foundation
import SwiftUI
import Observation

/// Tab options for iPhone tab view
enum AppTab: String, CaseIterable, Identifiable {
    case dashboard
    case events
    case recordings
    case debug
    case settings

    var id: String { rawValue }
}

/// Sidebar items for iPad navigation
enum SidebarItem: Hashable {
    case dashboard
    case events
    case recordings
    case camera(String)
    case debug
    case configuration
    case settings
}

/// Main application state manager.
/// Provides centralized state management for cameras, events, and connection status.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Navigation State

    @Published var selectedTab: AppTab = .dashboard
    @Published var selectedSidebarItem: SidebarItem? = .dashboard
    @Published var selectedCameraId: String?
    @Published var presentedEvent: Event?

    // MARK: - Data State

    @Published private(set) var cameras: [Camera] = []
    @Published private(set) var events: [Event] = []
    @Published private(set) var serverStats: ServerStats?
    @Published private(set) var frigateConfig: FrigateConfig?

    // MARK: - Connection State

    @Published private(set) var apiConnectionStatus: ConnectionStatus = .disconnected
    @Published private(set) var mqttConnectionStatus: ConnectionStatus = .disconnected
    @Published private(set) var lastError: AppError?

    // MARK: - UI State

    @Published var prefersDarkMode: Bool = false
    @Published var showsDetectionOverlays: Bool = true
    @Published var unreadEventCount: Int = 0

    // MARK: - Services

    private var apiService: FrigateAPIService?
    private var mqttService: MQTTService?
    private var currentServer: ServerConnection?

    // MARK: - Initialization

    init() {
        loadUserPreferences()
    }

    // MARK: - Connection Management

    /// Connect to a Frigate server
    func connect(to server: ServerConnection) async {
        currentServer = server
        apiConnectionStatus = .connecting
        mqttConnectionStatus = .connecting

        // Initialize API service
        apiService = FrigateAPIService(serverConnection: server)

        // Attempt initial data fetch
        do {
            // Fetch initial data in parallel
            async let camerasTask = apiService?.fetchCameras()
            async let configTask = apiService?.fetchConfig()
            async let statsTask = apiService?.fetchStats()

            let fetchedCameras = try await camerasTask ?? []
            let fetchedConfig = try await configTask
            let fetchedStats = try await statsTask

            cameras = fetchedCameras
            frigateConfig = fetchedConfig
            serverStats = fetchedStats
            apiConnectionStatus = .connected

            // Start MQTT connection if configured
            if let mqttConfig = server.mqttConfig {
                await connectMQTT(config: mqttConfig)
            }

            // Fetch initial events
            await refreshEvents()

        } catch {
            apiConnectionStatus = .error
            lastError = AppError.connectionFailed(error.localizedDescription)
        }
    }

    /// Connect to MQTT broker
    private func connectMQTT(config: MQTTConfig) async {
        mqttService = MQTTService(config: config)
        mqttService?.delegate = self

        do {
            try await mqttService?.connect()
            mqttConnectionStatus = .connected
        } catch {
            mqttConnectionStatus = .error
            lastError = AppError.mqttConnectionFailed(error.localizedDescription)
        }
    }

    /// Disconnect from current server
    func disconnect() {
        apiService = nil
        mqttService?.disconnect()
        mqttService = nil
        currentServer = nil
        apiConnectionStatus = .disconnected
        mqttConnectionStatus = .disconnected
        cameras = []
        events = []
        serverStats = nil
    }

    /// Reconnect all services (used when app becomes active)
    func reconnectServices() async {
        guard let server = currentServer else { return }

        // Reconnect MQTT if needed
        if mqttConnectionStatus != .connected, let mqttConfig = server.mqttConfig {
            await connectMQTT(config: mqttConfig)
        }

        // Refresh data
        await refreshAll()
    }

    /// Enter background mode (maintain MQTT for notifications)
    func enterBackground() {
        // MQTT service should continue running for notifications
        // Could implement reduced polling or pause non-essential updates
    }

    // MARK: - Data Refresh

    /// Refresh all data from server
    func refreshAll() async {
        async let camerasTask: () = refreshCameras()
        async let eventsTask: () = refreshEvents()
        async let statsTask: () = refreshStats()

        await camerasTask
        await eventsTask
        await statsTask
    }

    /// Refresh camera list
    func refreshCameras() async {
        guard let apiService else { return }
        do {
            cameras = try await apiService.fetchCameras()
        } catch {
            lastError = AppError.dataFetchFailed("cameras", error.localizedDescription)
        }
    }

    /// Refresh events with optional filter
    func refreshEvents(filter: EventFilter = .default) async {
        guard let apiService else { return }
        do {
            events = try await apiService.fetchEvents(filter: filter)
        } catch {
            lastError = AppError.dataFetchFailed("events", error.localizedDescription)
        }
    }

    /// Refresh server statistics
    func refreshStats() async {
        guard let apiService else { return }
        do {
            serverStats = try await apiService.fetchStats()
        } catch {
            lastError = AppError.dataFetchFailed("stats", error.localizedDescription)
        }
    }

    /// Refresh configuration
    func refreshConfig() async {
        guard let apiService else { return }
        do {
            frigateConfig = try await apiService.fetchConfig()
        } catch {
            lastError = AppError.dataFetchFailed("config", error.localizedDescription)
        }
    }

    // MARK: - Camera Actions

    /// Toggle recording for a camera
    func toggleRecording(for cameraId: String) async {
        guard let apiService else { return }
        guard let index = cameras.firstIndex(where: { $0.id == cameraId }) else { return }

        let newState = !cameras[index].config.record.enabled
        do {
            try await apiService.setCameraRecording(cameraId: cameraId, enabled: newState)
            cameras[index].config.record.enabled = newState
        } catch {
            lastError = AppError.actionFailed("toggle recording", error.localizedDescription)
        }
    }

    /// Toggle detection for a camera
    func toggleDetection(for cameraId: String) async {
        guard let apiService else { return }
        guard let index = cameras.firstIndex(where: { $0.id == cameraId }) else { return }

        let newState = !cameras[index].config.detect.enabled
        do {
            try await apiService.setCameraDetection(cameraId: cameraId, enabled: newState)
            cameras[index].config.detect.enabled = newState
        } catch {
            lastError = AppError.actionFailed("toggle detection", error.localizedDescription)
        }
    }

    /// Toggle motion detection for a camera
    func toggleMotionDetection(for cameraId: String) async {
        guard let apiService else { return }
        guard let index = cameras.firstIndex(where: { $0.id == cameraId }) else { return }

        let currentState = cameras[index].status.motionDetected
        do {
            try await apiService.setCameraMotionDetection(cameraId: cameraId, enabled: !currentState)
            await refreshCameras()
        } catch {
            lastError = AppError.actionFailed("toggle motion detection", error.localizedDescription)
        }
    }

    // MARK: - Event Actions

    /// Retain an event indefinitely
    func retainEvent(_ eventId: String) async {
        guard let apiService else { return }
        do {
            try await apiService.retainEvent(eventId: eventId, retain: true)
            if let index = events.firstIndex(where: { $0.id == eventId }) {
                events[index].isRetained = true
            }
        } catch {
            lastError = AppError.actionFailed("retain event", error.localizedDescription)
        }
    }

    /// Delete an event
    func deleteEvent(_ eventId: String) async {
        guard let apiService else { return }
        do {
            try await apiService.deleteEvent(eventId: eventId)
            events.removeAll { $0.id == eventId }
        } catch {
            lastError = AppError.actionFailed("delete event", error.localizedDescription)
        }
    }

    /// Mark events as read
    func markEventsAsRead() {
        unreadEventCount = 0
    }

    // MARK: - Configuration Actions

    /// Save configuration changes
    func saveConfiguration(_ config: FrigateConfig) async throws {
        guard let apiService else {
            throw AppError.notConnected
        }
        try await apiService.saveConfig(config)
        frigateConfig = config
    }

    /// Restart Frigate service
    func restartFrigate() async throws {
        guard let apiService else {
            throw AppError.notConnected
        }
        try await apiService.restartFrigate()
    }

    // MARK: - User Preferences

    private func loadUserPreferences() {
        prefersDarkMode = UserDefaults.standard.bool(forKey: "prefersDarkMode")
        showsDetectionOverlays = UserDefaults.standard.object(forKey: "showsDetectionOverlays") as? Bool ?? true
    }

    func saveUserPreferences() {
        UserDefaults.standard.set(prefersDarkMode, forKey: "prefersDarkMode")
        UserDefaults.standard.set(showsDetectionOverlays, forKey: "showsDetectionOverlays")
    }

    // MARK: - Error Handling

    func clearError() {
        lastError = nil
    }
}

// MARK: - MQTT Service Delegate

extension AppState: MQTTServiceDelegate {
    nonisolated func mqttService(_ service: MQTTService, didReceiveEvent event: Event) {
        Task { @MainActor in
            // Update or insert event
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                events[index] = event
            } else {
                events.insert(event, at: 0)
                unreadEventCount += 1

                // Trigger notification for new events
                await NotificationService.shared.scheduleEventNotification(event: event)
            }
        }
    }

    nonisolated func mqttService(_ service: MQTTService, didUpdateCameraStatus cameraId: String, status: CameraStatus) {
        Task { @MainActor in
            if let index = cameras.firstIndex(where: { $0.id == cameraId }) {
                cameras[index].status = status
            }
        }
    }

    nonisolated func mqttService(_ service: MQTTService, didChangeConnectionStatus status: ConnectionStatus) {
        Task { @MainActor in
            mqttConnectionStatus = status
        }
    }
}

// MARK: - App Errors

enum AppError: LocalizedError, Identifiable {
    case notConnected
    case connectionFailed(String)
    case mqttConnectionFailed(String)
    case dataFetchFailed(String, String)
    case actionFailed(String, String)
    case configurationError(String)
    case streamError(String)

    var id: String {
        switch self {
        case .notConnected: return "notConnected"
        case .connectionFailed(let msg): return "connectionFailed-\(msg)"
        case .mqttConnectionFailed(let msg): return "mqttConnectionFailed-\(msg)"
        case .dataFetchFailed(let type, _): return "dataFetchFailed-\(type)"
        case .actionFailed(let action, _): return "actionFailed-\(action)"
        case .configurationError(let msg): return "configurationError-\(msg)"
        case .streamError(let msg): return "streamError-\(msg)"
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a Frigate server"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .mqttConnectionFailed(let message):
            return "MQTT connection failed: \(message)"
        case .dataFetchFailed(let type, let message):
            return "Failed to fetch \(type): \(message)"
        case .actionFailed(let action, let message):
            return "Failed to \(action): \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .streamError(let message):
            return "Stream error: \(message)"
        }
    }
}
