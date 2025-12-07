import Foundation

/// Represents a detected activity or anomaly from the Frigate NVR.
struct Event: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let cameraName: String
    let label: String
    let subLabel: String?
    let zones: [String]
    let startTime: Date
    var endTime: Date?
    let score: Double
    let topScore: Double
    let thumbnail: String?
    var hasSnapshot: Bool
    var hasClip: Bool
    var isRetained: Bool
    var plusId: String?
    var modelHash: String?
    var detectorType: String?
    var data: EventData?
    var box: BoundingBox?

    /// Duration of the event in seconds
    var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    /// Formatted duration string
    var durationString: String {
        guard let duration else { return "Ongoing" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "N/A"
    }

    /// URL for the event's snapshot image
    func snapshotURL(baseURL: URL) -> URL? {
        guard hasSnapshot else { return nil }
        return baseURL.appendingPathComponent("api/events/\(id)/snapshot.jpg")
    }

    /// URL for the event's video clip
    func clipURL(baseURL: URL) -> URL? {
        guard hasClip else { return nil }
        return baseURL.appendingPathComponent("api/events/\(id)/clip.mp4")
    }

    /// URL for the event's thumbnail
    func thumbnailURL(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/events/\(id)/thumbnail.jpg")
    }

    init(
        id: String,
        cameraName: String,
        label: String,
        subLabel: String? = nil,
        zones: [String] = [],
        startTime: Date,
        endTime: Date? = nil,
        score: Double = 0,
        topScore: Double = 0,
        thumbnail: String? = nil,
        hasSnapshot: Bool = false,
        hasClip: Bool = false,
        isRetained: Bool = false,
        plusId: String? = nil,
        modelHash: String? = nil,
        detectorType: String? = nil,
        data: EventData? = nil,
        box: BoundingBox? = nil
    ) {
        self.id = id
        self.cameraName = cameraName
        self.label = label
        self.subLabel = subLabel
        self.zones = zones
        self.startTime = startTime
        self.endTime = endTime
        self.score = score
        self.topScore = topScore
        self.thumbnail = thumbnail
        self.hasSnapshot = hasSnapshot
        self.hasClip = hasClip
        self.isRetained = isRetained
        self.plusId = plusId
        self.modelHash = modelHash
        self.detectorType = detectorType
        self.data = data
        self.box = box
    }

    enum CodingKeys: String, CodingKey {
        case id
        case cameraName = "camera"
        case label
        case subLabel = "sub_label"
        case zones
        case startTime = "start_time"
        case endTime = "end_time"
        case score
        case topScore = "top_score"
        case thumbnail
        case hasSnapshot = "has_snapshot"
        case hasClip = "has_clip"
        case isRetained = "retain_indefinitely"
        case plusId = "plus_id"
        case modelHash = "model_hash"
        case detectorType = "detector_type"
        case data
        case box
    }
}

/// Additional event data
struct EventData: Codable, Hashable, Sendable {
    var type: String?
    var score: Double?
    var topScore: Double?
    var subLabel: String?
    var subLabelScore: Double?
    var attributes: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case score
        case topScore = "top_score"
        case subLabel = "sub_label"
        case subLabelScore = "sub_label_score"
        case attributes
    }
}

/// Bounding box coordinates for detected objects
struct BoundingBox: Codable, Hashable, Sendable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    var width: Double { x2 - x1 }
    var height: Double { y2 - y1 }
    var centerX: Double { (x1 + x2) / 2 }
    var centerY: Double { (y1 + y2) / 2 }
}

/// Event filter options for querying events
struct EventFilter: Equatable, Sendable {
    var cameras: Set<String>?
    var labels: Set<String>?
    var zones: Set<String>?
    var startTime: Date?
    var endTime: Date?
    var hasSnapshot: Bool?
    var hasClip: Bool?
    var isRetained: Bool?
    var limit: Int = 50
    var includesThumbnails: Bool = true

    static let `default` = EventFilter()

    /// Build query parameters for REST API
    func queryParameters() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let cameras, !cameras.isEmpty {
            items.append(URLQueryItem(name: "cameras", value: cameras.joined(separator: ",")))
        }

        if let labels, !labels.isEmpty {
            items.append(URLQueryItem(name: "labels", value: labels.joined(separator: ",")))
        }

        if let zones, !zones.isEmpty {
            items.append(URLQueryItem(name: "zones", value: zones.joined(separator: ",")))
        }

        if let startTime {
            items.append(URLQueryItem(name: "after", value: String(Int(startTime.timeIntervalSince1970))))
        }

        if let endTime {
            items.append(URLQueryItem(name: "before", value: String(Int(endTime.timeIntervalSince1970))))
        }

        if let hasSnapshot {
            items.append(URLQueryItem(name: "has_snapshot", value: hasSnapshot ? "1" : "0"))
        }

        if let hasClip {
            items.append(URLQueryItem(name: "has_clip", value: hasClip ? "1" : "0"))
        }

        if let isRetained {
            items.append(URLQueryItem(name: "include_thumbnails", value: isRetained ? "1" : "0"))
        }

        items.append(URLQueryItem(name: "limit", value: String(limit)))
        items.append(URLQueryItem(name: "include_thumbnails", value: includesThumbnails ? "1" : "0"))

        return items
    }
}

/// Summary of events for a time period
struct EventSummary: Codable, Sendable {
    let camera: String
    let day: String
    let label: String
    let zones: [String]
    let count: Int
}

// MARK: - MQTT Event Payload

/// Real-time event payload received via MQTT
struct MQTTEventPayload: Codable, Sendable {
    let before: MQTTEventState
    let after: MQTTEventState
    let type: String

    /// Whether this is a new event
    var isNew: Bool {
        type == "new"
    }

    /// Whether this is an event update
    var isUpdate: Bool {
        type == "update"
    }

    /// Whether this is an event end
    var isEnd: Bool {
        type == "end"
    }

    /// Convert to Event model
    func toEvent() -> Event {
        Event(
            id: after.id,
            cameraName: after.camera,
            label: after.label,
            subLabel: after.subLabel,
            zones: after.currentZones,
            startTime: Date(timeIntervalSince1970: after.startTime),
            endTime: after.endTime.map { Date(timeIntervalSince1970: $0) },
            score: after.score,
            topScore: after.topScore,
            hasSnapshot: after.hasSnapshot,
            hasClip: after.hasClip,
            isRetained: after.retainIndefinitely
        )
    }
}

/// State of an event in MQTT payload
struct MQTTEventState: Codable, Sendable {
    let id: String
    let camera: String
    let frameTime: Double
    let snapshotTime: Double?
    let label: String
    let subLabel: String?
    let topScore: Double
    let falsePositive: Bool
    let startTime: Double
    let endTime: Double?
    let score: Double
    let box: [Double]
    let area: Int
    let ratio: Double
    let region: [Double]
    let stationary: Bool
    let motionlessCount: Int
    let positionChanges: Int
    let currentZones: [String]
    let enteredZones: [String]
    let hasSnapshot: Bool
    let hasClip: Bool
    let retainIndefinitely: Bool
    let plusId: String?
    let modelHash: String?
    let detectorType: String?
    let modelType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case camera
        case frameTime = "frame_time"
        case snapshotTime = "snapshot_time"
        case label
        case subLabel = "sub_label"
        case topScore = "top_score"
        case falsePositive = "false_positive"
        case startTime = "start_time"
        case endTime = "end_time"
        case score
        case box
        case area
        case ratio
        case region
        case stationary
        case motionlessCount = "motionless_count"
        case positionChanges = "position_changes"
        case currentZones = "current_zones"
        case enteredZones = "entered_zones"
        case hasSnapshot = "has_snapshot"
        case hasClip = "has_clip"
        case retainIndefinitely = "retain_indefinitely"
        case plusId = "plus_id"
        case modelHash = "model_hash"
        case detectorType = "detector_type"
        case modelType = "model_type"
    }
}

// MARK: - Sample Data for Previews

extension Event {
    static let sample = Event(
        id: "1234567890.123456-abc123",
        cameraName: "front_door",
        label: "person",
        zones: ["front_yard", "driveway"],
        startTime: Date().addingTimeInterval(-300),
        endTime: Date().addingTimeInterval(-290),
        score: 0.89,
        topScore: 0.92,
        hasSnapshot: true,
        hasClip: true
    )

    static let samples: [Event] = [
        Event(id: "1", cameraName: "front_door", label: "person", zones: ["front_yard"], startTime: Date().addingTimeInterval(-300), endTime: Date().addingTimeInterval(-290), score: 0.89, topScore: 0.92, hasSnapshot: true, hasClip: true),
        Event(id: "2", cameraName: "driveway", label: "car", zones: ["driveway"], startTime: Date().addingTimeInterval(-600), endTime: Date().addingTimeInterval(-580), score: 0.95, topScore: 0.97, hasSnapshot: true, hasClip: true),
        Event(id: "3", cameraName: "back_yard", label: "dog", zones: ["back_yard"], startTime: Date().addingTimeInterval(-900), endTime: Date().addingTimeInterval(-870), score: 0.78, topScore: 0.82, hasSnapshot: true, hasClip: false),
        Event(id: "4", cameraName: "garage", label: "person", zones: ["garage"], startTime: Date().addingTimeInterval(-1200), endTime: Date().addingTimeInterval(-1180), score: 0.91, topScore: 0.94, hasSnapshot: true, hasClip: true)
    ]
}
