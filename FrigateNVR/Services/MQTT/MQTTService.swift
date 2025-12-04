import Foundation
import Combine

/// Protocol for receiving MQTT service callbacks
protocol MQTTServiceDelegate: AnyObject, Sendable {
    /// Called when a new event is received
    func mqttService(_ service: MQTTService, didReceiveEvent event: Event)

    /// Called when camera status is updated
    func mqttService(_ service: MQTTService, didUpdateCameraStatus cameraId: String, status: CameraStatus)

    /// Called when connection status changes
    func mqttService(_ service: MQTTService, didChangeConnectionStatus status: ConnectionStatus)
}

/// Service for managing MQTT connections to Frigate.
/// Handles real-time event notifications, camera status updates, and detection results.
final class MQTTService: @unchecked Sendable {
    private let config: MQTTConfig
    private var client: MQTTClientProtocol?
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    private var messageHandler: Task<Void, Never>?

    weak var delegate: MQTTServiceDelegate?

    /// Current connection status
    private(set) var connectionStatus: ConnectionStatus = .disconnected {
        didSet {
            delegate?.mqttService(self, didChangeConnectionStatus: connectionStatus)
        }
    }

    /// Subscribed topics
    private var subscribedTopics: Set<String> = []

    init(config: MQTTConfig) {
        self.config = config
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// Connect to the MQTT broker
    func connect() async throws {
        guard !isConnected else { return }

        connectionStatus = .connecting

        // Create MQTT client
        client = MQTTClient(
            host: config.host,
            port: config.port,
            clientId: config.clientId ?? "frigate-ios-\(UUID().uuidString.prefix(8))",
            useTLS: config.useTLS,
            username: config.username,
            password: config.password,
            keepAlive: UInt16(config.keepAliveInterval),
            cleanSession: config.cleanSession
        )

        client?.delegate = self

        do {
            try await client?.connect()
            isConnected = true
            connectionStatus = .connected

            // Subscribe to Frigate topics
            await subscribeToFrigateTopics()

            // Start message handling
            startMessageHandling()
        } catch {
            connectionStatus = .error
            throw error
        }
    }

    /// Disconnect from the MQTT broker
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        messageHandler?.cancel()
        messageHandler = nil

        client?.disconnect()
        client = nil
        isConnected = false
        connectionStatus = .disconnected
        subscribedTopics.removeAll()
    }

    /// Attempt to reconnect with exponential backoff
    private func attemptReconnect() {
        guard config.autoReconnect else { return }

        reconnectTask?.cancel()
        reconnectTask = Task {
            var delay: UInt64 = 1_000_000_000 // 1 second
            let maxDelay: UInt64 = 60_000_000_000 // 60 seconds

            while !Task.isCancelled && !isConnected {
                do {
                    try await Task.sleep(nanoseconds: delay)
                    try await connect()
                } catch {
                    delay = min(delay * 2, maxDelay)
                }
            }
        }
    }

    // MARK: - Topic Subscription

    /// Subscribe to standard Frigate MQTT topics
    private func subscribeToFrigateTopics() async {
        let prefix = config.topicPrefix

        // Standard Frigate topics
        let topics = [
            "\(prefix)/events",           // All events
            "\(prefix)/+/events",         // Per-camera events
            "\(prefix)/+/recordings/state", // Recording state changes
            "\(prefix)/+/detect/state",   // Detection state changes
            "\(prefix)/+/motion",         // Motion detection
            "\(prefix)/+/motion/state",   // Motion state changes
            "\(prefix)/+/snapshots/state", // Snapshot state changes
            "\(prefix)/+/audio/state",    // Audio detection state
            "\(prefix)/stats",            // Server statistics
            "\(prefix)/available"         // Frigate availability
        ]

        for topic in topics {
            await subscribe(to: topic)
        }
    }

    /// Subscribe to a specific topic
    func subscribe(to topic: String) async {
        guard !subscribedTopics.contains(topic) else { return }

        do {
            try await client?.subscribe(to: topic, qos: .atLeastOnce)
            subscribedTopics.insert(topic)
        } catch {
            print("Failed to subscribe to \(topic): \(error)")
        }
    }

    /// Unsubscribe from a topic
    func unsubscribe(from topic: String) async {
        guard subscribedTopics.contains(topic) else { return }

        do {
            try await client?.unsubscribe(from: topic)
            subscribedTopics.remove(topic)
        } catch {
            print("Failed to unsubscribe from \(topic): \(error)")
        }
    }

    /// Subscribe to events for a specific camera
    func subscribeToCamera(_ cameraId: String) async {
        let prefix = config.topicPrefix
        await subscribe(to: "\(prefix)/\(cameraId)/events")
        await subscribe(to: "\(prefix)/\(cameraId)/detect/state")
        await subscribe(to: "\(prefix)/\(cameraId)/recordings/state")
        await subscribe(to: "\(prefix)/\(cameraId)/motion")
    }

    /// Unsubscribe from a specific camera's events
    func unsubscribeFromCamera(_ cameraId: String) async {
        let prefix = config.topicPrefix
        await unsubscribe(from: "\(prefix)/\(cameraId)/events")
        await unsubscribe(from: "\(prefix)/\(cameraId)/detect/state")
        await unsubscribe(from: "\(prefix)/\(cameraId)/recordings/state")
        await unsubscribe(from: "\(prefix)/\(cameraId)/motion")
    }

    // MARK: - Message Handling

    private func startMessageHandling() {
        messageHandler = Task {
            guard let client else { return }

            for await message in client.messages {
                await handleMessage(message)
            }
        }
    }

    private func handleMessage(_ message: MQTTMessage) async {
        let topic = message.topic
        let prefix = config.topicPrefix

        // Parse topic to determine message type
        let topicParts = topic.split(separator: "/").map(String.init)

        guard topicParts.count >= 2 else { return }

        // Handle different message types
        if topic == "\(prefix)/events" || topic.hasSuffix("/events") {
            await handleEventMessage(message, topicParts: topicParts)
        } else if topic.hasSuffix("/detect/state") {
            await handleDetectStateMessage(message, topicParts: topicParts)
        } else if topic.hasSuffix("/recordings/state") {
            await handleRecordingsStateMessage(message, topicParts: topicParts)
        } else if topic.hasSuffix("/motion") {
            await handleMotionMessage(message, topicParts: topicParts)
        } else if topic == "\(prefix)/stats" {
            await handleStatsMessage(message)
        } else if topic == "\(prefix)/available" {
            await handleAvailabilityMessage(message)
        }
    }

    private func handleEventMessage(_ message: MQTTMessage, topicParts: [String]) async {
        guard let data = message.payload.data(using: .utf8) else { return }

        do {
            let payload = try JSONDecoder().decode(MQTTEventPayload.self, from: data)
            let event = payload.toEvent()
            delegate?.mqttService(self, didReceiveEvent: event)
        } catch {
            print("Failed to decode event message: \(error)")
        }
    }

    private func handleDetectStateMessage(_ message: MQTTMessage, topicParts: [String]) async {
        guard topicParts.count >= 3 else { return }
        let cameraId = topicParts[1]
        let enabled = message.payload.lowercased() == "on"

        let status = CameraStatus(detecting: enabled)
        delegate?.mqttService(self, didUpdateCameraStatus: cameraId, status: status)
    }

    private func handleRecordingsStateMessage(_ message: MQTTMessage, topicParts: [String]) async {
        guard topicParts.count >= 3 else { return }
        let cameraId = topicParts[1]
        let enabled = message.payload.lowercased() == "on"

        let status = CameraStatus(recording: enabled)
        delegate?.mqttService(self, didUpdateCameraStatus: cameraId, status: status)
    }

    private func handleMotionMessage(_ message: MQTTMessage, topicParts: [String]) async {
        guard topicParts.count >= 2 else { return }
        let cameraId = topicParts[1]
        let motionDetected = message.payload == "1" || message.payload.lowercased() == "on"

        let status = CameraStatus(motionDetected: motionDetected)
        delegate?.mqttService(self, didUpdateCameraStatus: cameraId, status: status)
    }

    private func handleStatsMessage(_ message: MQTTMessage) async {
        // Stats messages contain server statistics
        // Could be forwarded to app state for display
    }

    private func handleAvailabilityMessage(_ message: MQTTMessage) async {
        let available = message.payload.lowercased() == "online"
        if !available {
            connectionStatus = .error
        }
    }

    // MARK: - Publishing

    /// Publish a message to a topic
    func publish(to topic: String, message: String, retain: Bool = false) async throws {
        try await client?.publish(to: topic, message: message, qos: .atLeastOnce, retain: retain)
    }

    /// Set camera detection state via MQTT
    func setCameraDetection(cameraId: String, enabled: Bool) async throws {
        let topic = "\(config.topicPrefix)/\(cameraId)/detect/set"
        try await publish(to: topic, message: enabled ? "ON" : "OFF")
    }

    /// Set camera recording state via MQTT
    func setCameraRecording(cameraId: String, enabled: Bool) async throws {
        let topic = "\(config.topicPrefix)/\(cameraId)/recordings/set"
        try await publish(to: topic, message: enabled ? "ON" : "OFF")
    }

    /// Set camera snapshots state via MQTT
    func setCameraSnapshots(cameraId: String, enabled: Bool) async throws {
        let topic = "\(config.topicPrefix)/\(cameraId)/snapshots/set"
        try await publish(to: topic, message: enabled ? "ON" : "OFF")
    }

    /// Set camera motion detection state via MQTT
    func setCameraMotionDetection(cameraId: String, enabled: Bool) async throws {
        let topic = "\(config.topicPrefix)/\(cameraId)/motion/set"
        try await publish(to: topic, message: enabled ? "ON" : "OFF")
    }
}

// MARK: - MQTT Client Delegate

extension MQTTService: MQTTClientDelegate {
    func mqttClientDidConnect(_ client: MQTTClientProtocol) {
        isConnected = true
        connectionStatus = .connected
    }

    func mqttClientDidDisconnect(_ client: MQTTClientProtocol, error: Error?) {
        isConnected = false
        connectionStatus = error != nil ? .error : .disconnected
        attemptReconnect()
    }

    func mqttClient(_ client: MQTTClientProtocol, didReceiveMessage message: MQTTMessage) {
        Task {
            await handleMessage(message)
        }
    }
}

// MARK: - MQTT Types

/// MQTT message representation
struct MQTTMessage: Sendable {
    let topic: String
    let payload: String
    let qos: MQTTQoS
    let retain: Bool
}

/// MQTT Quality of Service levels
enum MQTTQoS: Int, Sendable {
    case atMostOnce = 0
    case atLeastOnce = 1
    case exactlyOnce = 2
}

// MARK: - MQTT Client Protocol

/// Protocol for MQTT client implementations
protocol MQTTClientProtocol: AnyObject, Sendable {
    var delegate: MQTTClientDelegate? { get set }
    var messages: AsyncStream<MQTTMessage> { get }

    func connect() async throws
    func disconnect()
    func subscribe(to topic: String, qos: MQTTQoS) async throws
    func unsubscribe(from topic: String) async throws
    func publish(to topic: String, message: String, qos: MQTTQoS, retain: Bool) async throws
}

/// Protocol for MQTT client delegate callbacks
protocol MQTTClientDelegate: AnyObject {
    func mqttClientDidConnect(_ client: MQTTClientProtocol)
    func mqttClientDidDisconnect(_ client: MQTTClientProtocol, error: Error?)
    func mqttClient(_ client: MQTTClientProtocol, didReceiveMessage message: MQTTMessage)
}

// MARK: - MQTT Client Implementation

/// Concrete MQTT client implementation using CocoaMQTT
final class MQTTClient: MQTTClientProtocol, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let clientId: String
    private let useTLS: Bool
    private let username: String?
    private let password: String?
    private let keepAlive: UInt16
    private let cleanSession: Bool

    weak var delegate: MQTTClientDelegate?

    private var messageContinuation: AsyncStream<MQTTMessage>.Continuation?
    private(set) lazy var messages: AsyncStream<MQTTMessage> = {
        AsyncStream { continuation in
            self.messageContinuation = continuation
        }
    }()

    // CocoaMQTT client would be used here
    // private var mqttClient: CocoaMQTT5?

    init(
        host: String,
        port: Int,
        clientId: String,
        useTLS: Bool,
        username: String?,
        password: String?,
        keepAlive: UInt16,
        cleanSession: Bool
    ) {
        self.host = host
        self.port = port
        self.clientId = clientId
        self.useTLS = useTLS
        self.username = username
        self.password = password
        self.keepAlive = keepAlive
        self.cleanSession = cleanSession
    }

    func connect() async throws {
        // Implementation would use CocoaMQTT
        // For now, simulate connection
        try await Task.sleep(nanoseconds: 100_000_000)
        delegate?.mqttClientDidConnect(self)
    }

    func disconnect() {
        messageContinuation?.finish()
        delegate?.mqttClientDidDisconnect(self, error: nil)
    }

    func subscribe(to topic: String, qos: MQTTQoS) async throws {
        // Implementation would use CocoaMQTT
    }

    func unsubscribe(from topic: String) async throws {
        // Implementation would use CocoaMQTT
    }

    func publish(to topic: String, message: String, qos: MQTTQoS, retain: Bool) async throws {
        // Implementation would use CocoaMQTT
    }

    // MARK: - Internal message handling

    fileprivate func handleReceivedMessage(topic: String, payload: String, qos: Int, retain: Bool) {
        let message = MQTTMessage(
            topic: topic,
            payload: payload,
            qos: MQTTQoS(rawValue: qos) ?? .atMostOnce,
            retain: retain
        )
        messageContinuation?.yield(message)
        delegate?.mqttClient(self, didReceiveMessage: message)
    }
}
