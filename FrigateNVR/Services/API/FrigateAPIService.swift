import Foundation

/// Service for communicating with the Frigate NVR REST API.
/// Handles all HTTP requests for configuration, events, and camera management.
actor FrigateAPIService {
    private let session: URLSession
    private let serverConnection: ServerConnection
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    /// Base URL for API requests
    private var baseURL: URL {
        serverConnection.apiURL
    }

    init(serverConnection: ServerConnection) {
        self.serverConnection = serverConnection

        // Configure URL session with appropriate timeouts
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)

        // Configure JSON decoder with custom date handling
        self.jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            if let dateString = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date")
        }

        self.jsonEncoder = JSONEncoder()
    }

    // MARK: - Request Building

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Add API key if configured
        if let apiKey = serverConnection.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func performVoid(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Connection Testing

    /// Test connection to the Frigate server
    func testConnection() async -> ConnectionTestResult {
        let startTime = Date()

        do {
            let request = try makeRequest(path: "version")
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .failure("Server returned an error response")
            }

            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Also fetch camera count
            let cameras = try? await fetchCameras()

            return .success(
                latencyMs: latencyMs,
                serverVersion: version,
                cameraCount: cameras?.count
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Camera Endpoints

    /// Fetch all cameras
    func fetchCameras() async throws -> [Camera] {
        let request = try makeRequest(path: "config")
        let config: FrigateConfig = try await perform(request)

        var cameras: [Camera] = []
        for (name, cameraConfig) in config.cameras ?? [:] {
            // Build RTSP URL
            let rtspURL: URL? = {
                if let rtspBase = serverConnection.rtspBaseURL {
                    return rtspBase.appendingPathComponent(name)
                }
                return nil
            }()

            // Build snapshot URL
            let snapshotURL = baseURL.appendingPathComponent("\(name)/latest.jpg")

            let camera = Camera(
                id: name,
                name: name,
                streamURL: rtspURL,
                snapshotURL: snapshotURL,
                config: CameraConfig(
                    detect: cameraConfig.detect ?? DetectionConfig(),
                    record: cameraConfig.record ?? RecordConfig(),
                    snapshots: cameraConfig.snapshots ?? SnapshotConfig(),
                    motion: cameraConfig.motion ?? MotionConfig(),
                    zones: cameraConfig.zones ?? [:],
                    objects: cameraConfig.objects ?? ObjectConfig()
                )
            )
            cameras.append(camera)
        }

        return cameras.sorted { $0.name < $1.name }
    }

    /// Fetch camera status
    func fetchCameraStats(cameraId: String) async throws -> CameraStats {
        let request = try makeRequest(path: "\(cameraId)/stats")
        return try await perform(request)
    }

    /// Get latest snapshot for a camera
    func fetchSnapshot(cameraId: String, height: Int? = nil, boundingBox: Bool? = nil) async throws -> Data {
        var queryItems: [URLQueryItem] = []
        if let height {
            queryItems.append(URLQueryItem(name: "h", value: String(height)))
        }
        if let boundingBox {
            queryItems.append(URLQueryItem(name: "bbox", value: boundingBox ? "1" : "0"))
        }

        let request = try makeRequest(path: "\(cameraId)/latest.jpg", queryItems: queryItems.isEmpty ? nil : queryItems)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return data
    }

    // MARK: - Camera Control

    /// Set recording state for a camera
    func setCameraRecording(cameraId: String, enabled: Bool) async throws {
        let request = try makeRequest(
            path: "\(cameraId)/recordings/\(enabled ? "enable" : "disable")",
            method: "POST"
        )
        try await performVoid(request)
    }

    /// Set detection state for a camera
    func setCameraDetection(cameraId: String, enabled: Bool) async throws {
        let request = try makeRequest(
            path: "\(cameraId)/detect/\(enabled ? "enable" : "disable")",
            method: "POST"
        )
        try await performVoid(request)
    }

    /// Set motion detection state for a camera
    func setCameraMotionDetection(cameraId: String, enabled: Bool) async throws {
        let request = try makeRequest(
            path: "\(cameraId)/motion/\(enabled ? "enable" : "disable")",
            method: "POST"
        )
        try await performVoid(request)
    }

    /// Set snapshot state for a camera
    func setCameraSnapshots(cameraId: String, enabled: Bool) async throws {
        let request = try makeRequest(
            path: "\(cameraId)/snapshots/\(enabled ? "enable" : "disable")",
            method: "POST"
        )
        try await performVoid(request)
    }

    // MARK: - Event Endpoints

    /// Fetch events with optional filter
    func fetchEvents(filter: EventFilter = .default) async throws -> [Event] {
        let request = try makeRequest(path: "events", queryItems: filter.queryParameters())
        return try await perform(request)
    }

    /// Fetch a single event by ID
    func fetchEvent(eventId: String) async throws -> Event {
        let request = try makeRequest(path: "events/\(eventId)")
        return try await perform(request)
    }

    /// Fetch event summary
    func fetchEventSummary(hasSnapshot: Bool? = nil, hasClip: Bool? = nil, timezone: String? = nil) async throws -> [EventSummary] {
        var queryItems: [URLQueryItem] = []
        if let hasSnapshot {
            queryItems.append(URLQueryItem(name: "has_snapshot", value: hasSnapshot ? "1" : "0"))
        }
        if let hasClip {
            queryItems.append(URLQueryItem(name: "has_clip", value: hasClip ? "1" : "0"))
        }
        if let timezone {
            queryItems.append(URLQueryItem(name: "timezone", value: timezone))
        }

        let request = try makeRequest(path: "events/summary", queryItems: queryItems.isEmpty ? nil : queryItems)
        return try await perform(request)
    }

    /// Retain or unretain an event
    func retainEvent(eventId: String, retain: Bool) async throws {
        let request = try makeRequest(
            path: "events/\(eventId)/retain",
            method: "POST",
            body: try jsonEncoder.encode(["retain": retain])
        )
        try await performVoid(request)
    }

    /// Delete an event
    func deleteEvent(eventId: String) async throws {
        let request = try makeRequest(path: "events/\(eventId)", method: "DELETE")
        try await performVoid(request)
    }

    /// Get event snapshot
    func fetchEventSnapshot(eventId: String) async throws -> Data {
        let request = try makeRequest(path: "events/\(eventId)/snapshot.jpg")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return data
    }

    /// Get event thumbnail
    func fetchEventThumbnail(eventId: String) async throws -> Data {
        let request = try makeRequest(path: "events/\(eventId)/thumbnail.jpg")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return data
    }

    /// Get event clip URL
    func eventClipURL(eventId: String) -> URL {
        baseURL.appendingPathComponent("events/\(eventId)/clip.mp4")
    }

    // MARK: - Recording Endpoints

    /// Fetch recording summary
    func fetchRecordingSummary(cameraId: String? = nil, timezone: String? = nil) async throws -> [RecordingSummary] {
        var path = "recordings/summary"
        if let cameraId {
            path = "\(cameraId)/recordings/summary"
        }

        var queryItems: [URLQueryItem] = []
        if let timezone {
            queryItems.append(URLQueryItem(name: "timezone", value: timezone))
        }

        let request = try makeRequest(path: path, queryItems: queryItems.isEmpty ? nil : queryItems)
        return try await perform(request)
    }

    /// Fetch recording segments
    func fetchRecordings(cameraId: String, after: Date? = nil, before: Date? = nil) async throws -> [RecordingSegment] {
        var queryItems: [URLQueryItem] = []
        if let after {
            queryItems.append(URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))))
        }
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: String(Int(before.timeIntervalSince1970))))
        }

        let request = try makeRequest(path: "\(cameraId)/recordings", queryItems: queryItems.isEmpty ? nil : queryItems)
        return try await perform(request)
    }

    /// Get recording playback URL for VOD
    func recordingVODURL(cameraId: String, startTime: Date, endTime: Date) -> URL {
        let start = Int(startTime.timeIntervalSince1970)
        let end = Int(endTime.timeIntervalSince1970)
        return baseURL.appendingPathComponent("vod/\(cameraId)/start/\(start)/end/\(end)/index.m3u8")
    }

    // MARK: - Configuration Endpoints

    /// Fetch Frigate configuration
    func fetchConfig() async throws -> FrigateConfig {
        let request = try makeRequest(path: "config")
        return try await perform(request)
    }

    /// Fetch raw configuration as text
    func fetchRawConfig() async throws -> String {
        let request = try makeRequest(path: "config/raw")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.invalidResponse
        }

        return text
    }

    /// Save configuration
    func saveConfig(_ config: FrigateConfig) async throws {
        let data = try jsonEncoder.encode(config)
        let request = try makeRequest(path: "config/save", method: "POST", body: data)
        try await performVoid(request)
    }

    /// Save raw configuration text
    func saveRawConfig(_ configText: String) async throws {
        guard let data = configText.data(using: .utf8) else {
            throw APIError.invalidRequest
        }

        var request = try makeRequest(path: "config/save", method: "POST")
        request.httpBody = data
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        try await performVoid(request)
    }

    // MARK: - System Endpoints

    /// Fetch server statistics
    func fetchStats() async throws -> ServerStats {
        let request = try makeRequest(path: "stats")
        return try await perform(request)
    }

    /// Fetch server version
    func fetchVersion() async throws -> String {
        let request = try makeRequest(path: "version")
        let (data, _) = try await session.data(for: request)
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
    }

    /// Restart Frigate
    func restartFrigate() async throws {
        let request = try makeRequest(path: "restart", method: "POST")
        try await performVoid(request)
    }

    /// Fetch available labels
    func fetchLabels() async throws -> [String] {
        let request = try makeRequest(path: "labels")
        return try await perform(request)
    }

    /// Fetch sub-labels for a label
    func fetchSubLabels(label: String? = nil) async throws -> [String] {
        var queryItems: [URLQueryItem] = []
        if let label {
            queryItems.append(URLQueryItem(name: "label", value: label))
        }
        let request = try makeRequest(path: "sub_labels", queryItems: queryItems.isEmpty ? nil : queryItems)
        return try await perform(request)
    }

    // MARK: - PTZ Control

    /// Send PTZ command
    func sendPTZCommand(cameraId: String, command: String, arg: String? = nil) async throws {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "command", value: command))
        if let arg {
            queryItems.append(URLQueryItem(name: "arg", value: arg))
        }

        let request = try makeRequest(path: "\(cameraId)/ptz", method: "POST", queryItems: queryItems)
        try await performVoid(request)
    }

    /// Move PTZ to preset
    func movePTZToPreset(cameraId: String, preset: String) async throws {
        try await sendPTZCommand(cameraId: cameraId, command: "preset", arg: preset)
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidRequest:
            return "Invalid request"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let data):
            if let data, let message = String(data: data, encoding: .utf8) {
                return "HTTP \(statusCode): \(message)"
            }
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
