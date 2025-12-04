import Foundation

/// Represents a connection configuration to a Frigate NVR server.
struct ServerConnection: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var baseURL: URL
    var apiKey: String?
    var mqttConfig: MQTTConfig?
    var isDefault: Bool
    var lastConnected: Date?
    var connectionStatus: ConnectionStatus

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        apiKey: String? = nil,
        mqttConfig: MQTTConfig? = nil,
        isDefault: Bool = false,
        lastConnected: Date? = nil,
        connectionStatus: ConnectionStatus = .disconnected
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.mqttConfig = mqttConfig
        self.isDefault = isDefault
        self.lastConnected = lastConnected
        self.connectionStatus = connectionStatus
    }

    /// The API base URL
    var apiURL: URL {
        baseURL.appendingPathComponent("api")
    }

    /// RTSP stream base URL (derived from base URL)
    var rtspBaseURL: URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "rtsp"
        components.port = 8554
        return components.url
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL = "base_url"
        case apiKey = "api_key"
        case mqttConfig = "mqtt_config"
        case isDefault = "is_default"
        case lastConnected = "last_connected"
        case connectionStatus = "connection_status"
    }
}

/// MQTT connection configuration
struct MQTTConfig: Codable, Hashable, Sendable {
    var host: String
    var port: Int
    var username: String?
    var password: String?
    var useTLS: Bool
    var clientId: String?
    var topicPrefix: String
    var keepAliveInterval: Int
    var cleanSession: Bool
    var autoReconnect: Bool

    init(
        host: String,
        port: Int = 1883,
        username: String? = nil,
        password: String? = nil,
        useTLS: Bool = false,
        clientId: String? = nil,
        topicPrefix: String = "frigate",
        keepAliveInterval: Int = 60,
        cleanSession: Bool = true,
        autoReconnect: Bool = true
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
        self.clientId = clientId ?? "frigate-ios-\(UUID().uuidString.prefix(8))"
        self.topicPrefix = topicPrefix
        self.keepAliveInterval = keepAliveInterval
        self.cleanSession = cleanSession
        self.autoReconnect = autoReconnect
    }

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case username
        case password
        case useTLS = "use_tls"
        case clientId = "client_id"
        case topicPrefix = "topic_prefix"
        case keepAliveInterval = "keep_alive_interval"
        case cleanSession = "clean_session"
        case autoReconnect = "auto_reconnect"
    }
}

/// Connection status for a server
enum ConnectionStatus: String, Codable, Sendable {
    case connected
    case connecting
    case disconnected
    case error

    var displayName: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .connected: return "wifi"
        case .connecting: return "wifi.exclamationmark"
        case .disconnected: return "wifi.slash"
        case .error: return "exclamationmark.triangle"
        }
    }

    var color: String {
        switch self {
        case .connected: return "green"
        case .connecting: return "yellow"
        case .disconnected: return "gray"
        case .error: return "red"
        }
    }
}

/// Result of a connection test
struct ConnectionTestResult: Sendable {
    let success: Bool
    let message: String
    let latencyMs: Int?
    let serverVersion: String?
    let cameraCount: Int?

    static func success(latencyMs: Int, serverVersion: String?, cameraCount: Int?) -> ConnectionTestResult {
        ConnectionTestResult(
            success: true,
            message: "Connection successful",
            latencyMs: latencyMs,
            serverVersion: serverVersion,
            cameraCount: cameraCount
        )
    }

    static func failure(_ message: String) -> ConnectionTestResult {
        ConnectionTestResult(
            success: false,
            message: message,
            latencyMs: nil,
            serverVersion: nil,
            cameraCount: nil
        )
    }
}

// MARK: - Sample Data for Previews

extension ServerConnection {
    static let sample = ServerConnection(
        name: "Home Frigate",
        baseURL: URL(string: "http://192.168.1.100:5000")!,
        apiKey: nil,
        mqttConfig: MQTTConfig(host: "192.168.1.100", port: 1883),
        isDefault: true,
        connectionStatus: .connected
    )

    static let samples: [ServerConnection] = [
        ServerConnection(
            name: "Home Frigate",
            baseURL: URL(string: "http://192.168.1.100:5000")!,
            mqttConfig: MQTTConfig(host: "192.168.1.100"),
            isDefault: true,
            connectionStatus: .connected
        ),
        ServerConnection(
            name: "Office NVR",
            baseURL: URL(string: "http://10.0.0.50:5000")!,
            mqttConfig: MQTTConfig(host: "10.0.0.50"),
            isDefault: false,
            connectionStatus: .disconnected
        )
    ]
}
