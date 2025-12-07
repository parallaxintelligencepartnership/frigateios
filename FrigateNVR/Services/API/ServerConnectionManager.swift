import Foundation
import SwiftUI

/// Manages server connections and persistence.
/// Handles storing, retrieving, and managing multiple Frigate server configurations.
@MainActor
final class ServerConnectionManager: ObservableObject {
    @Published private(set) var servers: [ServerConnection] = []
    @Published private(set) var activeServer: ServerConnection?
    @Published private(set) var isLoading: Bool = false
    @Published var lastTestResult: ConnectionTestResult?

    private let userDefaults = UserDefaults.standard
    private let serversKey = "frigate_servers"

    /// Whether any servers are configured
    var hasConfiguredServers: Bool {
        !servers.isEmpty
    }

    /// The default server, if one exists
    var defaultServer: ServerConnection? {
        servers.first { $0.isDefault } ?? servers.first
    }

    init() {
        loadServers()
    }

    // MARK: - Persistence

    /// Load servers from UserDefaults
    private func loadServers() {
        guard let data = userDefaults.data(forKey: serversKey) else { return }

        do {
            servers = try JSONDecoder().decode([ServerConnection].self, from: data)
        } catch {
            print("Failed to load servers: \(error)")
        }
    }

    /// Save servers to UserDefaults
    private func saveServers() {
        do {
            let data = try JSONEncoder().encode(servers)
            userDefaults.set(data, forKey: serversKey)
        } catch {
            print("Failed to save servers: \(error)")
        }
    }

    // MARK: - Server Management

    /// Add a new server configuration
    func addServer(_ server: ServerConnection) {
        var newServer = server

        // If this is the first server or marked as default, ensure it's the only default
        if servers.isEmpty || newServer.isDefault {
            servers = servers.map { s in
                var updated = s
                updated.isDefault = false
                return updated
            }
            newServer.isDefault = true
        }

        servers.append(newServer)
        saveServers()
    }

    /// Update an existing server configuration
    func updateServer(_ server: ServerConnection) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }

        var updatedServer = server

        // Handle default flag
        if updatedServer.isDefault {
            servers = servers.map { s in
                var updated = s
                updated.isDefault = (s.id == server.id)
                return updated
            }
        }

        servers[index] = updatedServer
        saveServers()

        // Update active server if it was the one modified
        if activeServer?.id == server.id {
            activeServer = updatedServer
        }
    }

    /// Delete a server configuration
    func deleteServer(_ server: ServerConnection) {
        servers.removeAll { $0.id == server.id }

        // If we deleted the default, make the first remaining server the default
        if server.isDefault, let first = servers.first {
            var updated = first
            updated.isDefault = true
            servers[0] = updated
        }

        saveServers()

        // Clear active server if it was deleted
        if activeServer?.id == server.id {
            activeServer = nil
        }
    }

    /// Set a server as the default
    func setDefaultServer(_ server: ServerConnection) {
        servers = servers.map { s in
            var updated = s
            updated.isDefault = (s.id == server.id)
            return updated
        }
        saveServers()
    }

    // MARK: - Connection Testing

    /// Test connection to a server
    func testConnection(to server: ServerConnection) async -> ConnectionTestResult {
        isLoading = true
        defer { isLoading = false }

        let apiService = FrigateAPIService(serverConnection: server)
        let result = await apiService.testConnection()
        lastTestResult = result
        return result
    }

    // MARK: - Active Server Management

    /// Set the active server and initiate connection
    func setActiveServer(_ server: ServerConnection) {
        var updated = server
        updated.lastConnected = Date()
        updated.connectionStatus = .connecting

        activeServer = updated

        // Update in servers list
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = updated
            saveServers()
        }
    }

    /// Update the connection status of the active server
    func updateConnectionStatus(_ status: ConnectionStatus) {
        guard var server = activeServer else { return }
        server.connectionStatus = status
        activeServer = server

        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }

    /// Disconnect from the active server
    func disconnectActiveServer() {
        guard var server = activeServer else { return }
        server.connectionStatus = .disconnected
        activeServer = nil

        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }
}

// MARK: - Server Form Data

/// Form data for creating/editing a server connection
struct ServerFormData: Equatable {
    var name: String = ""
    var baseURLString: String = ""
    var apiKey: String = ""
    var mqttHost: String = ""
    var mqttPort: String = "1883"
    var mqttUsername: String = ""
    var mqttPassword: String = ""
    var mqttUseTLS: Bool = false
    var mqttTopicPrefix: String = "frigate"
    var isDefault: Bool = false

    /// Create from existing server connection
    init(from server: ServerConnection? = nil) {
        guard let server else { return }

        name = server.name
        baseURLString = server.baseURL.absoluteString
        apiKey = server.apiKey ?? ""
        isDefault = server.isDefault

        if let mqtt = server.mqttConfig {
            mqttHost = mqtt.host
            mqttPort = String(mqtt.port)
            mqttUsername = mqtt.username ?? ""
            mqttPassword = mqtt.password ?? ""
            mqttUseTLS = mqtt.useTLS
            mqttTopicPrefix = mqtt.topicPrefix
        }
    }

    /// Validate the form data
    var isValid: Bool {
        !name.isEmpty && URL(string: baseURLString) != nil
    }

    /// Convert to ServerConnection
    func toServerConnection(existingId: UUID? = nil) -> ServerConnection? {
        guard let baseURL = URL(string: baseURLString) else { return nil }

        let mqttConfig: MQTTConfig? = {
            guard !mqttHost.isEmpty else { return nil }
            return MQTTConfig(
                host: mqttHost,
                port: Int(mqttPort) ?? 1883,
                username: mqttUsername.isEmpty ? nil : mqttUsername,
                password: mqttPassword.isEmpty ? nil : mqttPassword,
                useTLS: mqttUseTLS,
                topicPrefix: mqttTopicPrefix
            )
        }()

        return ServerConnection(
            id: existingId ?? UUID(),
            name: name,
            baseURL: baseURL,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            mqttConfig: mqttConfig,
            isDefault: isDefault
        )
    }
}
