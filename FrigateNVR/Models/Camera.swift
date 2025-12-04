import Foundation

/// Represents a single video source and its associated configuration from the Frigate NVR.
struct Camera: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    var streamURL: URL?
    var snapshotURL: URL?
    var config: CameraConfig
    var status: CameraStatus

    /// Whether the camera is currently recording
    var isRecording: Bool {
        status.recording
    }

    /// Whether detection is enabled for this camera
    var isDetecting: Bool {
        config.detect.enabled
    }

    /// Whether the camera is currently online
    var isOnline: Bool {
        status.cameraFps > 0
    }

    init(
        id: String,
        name: String,
        streamURL: URL? = nil,
        snapshotURL: URL? = nil,
        config: CameraConfig = CameraConfig(),
        status: CameraStatus = CameraStatus()
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.snapshotURL = snapshotURL
        self.config = config
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case streamURL = "stream_url"
        case snapshotURL = "snapshot_url"
        case config
        case status
    }
}

/// Camera configuration settings
struct CameraConfig: Codable, Hashable, Sendable {
    var detect: DetectionConfig
    var record: RecordConfig
    var snapshots: SnapshotConfig
    var motion: MotionConfig
    var zones: [String: ZoneConfig]
    var objects: ObjectConfig
    var ffmpegInputs: [FFmpegInput]

    init(
        detect: DetectionConfig = DetectionConfig(),
        record: RecordConfig = RecordConfig(),
        snapshots: SnapshotConfig = SnapshotConfig(),
        motion: MotionConfig = MotionConfig(),
        zones: [String: ZoneConfig] = [:],
        objects: ObjectConfig = ObjectConfig(),
        ffmpegInputs: [FFmpegInput] = []
    ) {
        self.detect = detect
        self.record = record
        self.snapshots = snapshots
        self.motion = motion
        self.zones = zones
        self.objects = objects
        self.ffmpegInputs = ffmpegInputs
    }

    enum CodingKeys: String, CodingKey {
        case detect
        case record
        case snapshots
        case motion
        case zones
        case objects
        case ffmpegInputs = "ffmpeg_inputs"
    }
}

/// Detection configuration
struct DetectionConfig: Codable, Hashable, Sendable {
    var enabled: Bool
    var width: Int?
    var height: Int?
    var fps: Int?
    var maxDisappeared: Int?
    var stationary: StationaryConfig?

    init(
        enabled: Bool = true,
        width: Int? = nil,
        height: Int? = nil,
        fps: Int? = nil,
        maxDisappeared: Int? = nil,
        stationary: StationaryConfig? = nil
    ) {
        self.enabled = enabled
        self.width = width
        self.height = height
        self.fps = fps
        self.maxDisappeared = maxDisappeared
        self.stationary = stationary
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case width
        case height
        case fps
        case maxDisappeared = "max_disappeared"
        case stationary
    }
}

/// Stationary object detection configuration
struct StationaryConfig: Codable, Hashable, Sendable {
    var interval: Int?
    var threshold: Int?
    var maxFramesWithoutUpdate: Int?

    enum CodingKeys: String, CodingKey {
        case interval
        case threshold
        case maxFramesWithoutUpdate = "max_frames_without_update"
    }
}

/// Recording configuration
struct RecordConfig: Codable, Hashable, Sendable {
    var enabled: Bool
    var retainDays: Int?
    var events: RecordEventsConfig?

    init(enabled: Bool = false, retainDays: Int? = nil, events: RecordEventsConfig? = nil) {
        self.enabled = enabled
        self.retainDays = retainDays
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case retainDays = "retain_days"
        case events
    }
}

/// Recording events configuration
struct RecordEventsConfig: Codable, Hashable, Sendable {
    var preCapture: Int?
    var postCapture: Int?
    var retainDefault: Int?
    var retainMode: String?

    enum CodingKeys: String, CodingKey {
        case preCapture = "pre_capture"
        case postCapture = "post_capture"
        case retainDefault = "retain_default"
        case retainMode = "retain_mode"
    }
}

/// Snapshot configuration
struct SnapshotConfig: Codable, Hashable, Sendable {
    var enabled: Bool
    var cleanCopy: Bool?
    var timestamp: Bool?
    var boundingBox: Bool?
    var crop: Bool?
    var requiredZones: [String]?
    var height: Int?
    var retainDays: Int?

    init(enabled: Bool = true, cleanCopy: Bool? = nil, timestamp: Bool? = nil, boundingBox: Bool? = nil, crop: Bool? = nil, requiredZones: [String]? = nil, height: Int? = nil, retainDays: Int? = nil) {
        self.enabled = enabled
        self.cleanCopy = cleanCopy
        self.timestamp = timestamp
        self.boundingBox = boundingBox
        self.crop = crop
        self.requiredZones = requiredZones
        self.height = height
        self.retainDays = retainDays
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case cleanCopy = "clean_copy"
        case timestamp
        case boundingBox = "bounding_box"
        case crop
        case requiredZones = "required_zones"
        case height
        case retainDays = "retain_days"
    }
}

/// Motion detection configuration
struct MotionConfig: Codable, Hashable, Sendable {
    var threshold: Int?
    var contourArea: Int?
    var deltaAlpha: Double?
    var frameAlpha: Double?
    var frameHeight: Int?
    var improvContrast: Bool?
    var mask: [String]?

    init(
        threshold: Int? = nil,
        contourArea: Int? = nil,
        deltaAlpha: Double? = nil,
        frameAlpha: Double? = nil,
        frameHeight: Int? = nil,
        improvContrast: Bool? = nil,
        mask: [String]? = nil
    ) {
        self.threshold = threshold
        self.contourArea = contourArea
        self.deltaAlpha = deltaAlpha
        self.frameAlpha = frameAlpha
        self.frameHeight = frameHeight
        self.improvContrast = improvContrast
        self.mask = mask
    }

    enum CodingKeys: String, CodingKey {
        case threshold
        case contourArea = "contour_area"
        case deltaAlpha = "delta_alpha"
        case frameAlpha = "frame_alpha"
        case frameHeight = "frame_height"
        case improvContrast = "improve_contrast"
        case mask
    }
}

/// Zone configuration for detection areas
struct ZoneConfig: Codable, Hashable, Sendable {
    var coordinates: String
    var objects: [String]?
    var filters: [String: ZoneFilterConfig]?
    var inertia: Int?
    var loiteringTime: Int?

    enum CodingKeys: String, CodingKey {
        case coordinates
        case objects
        case filters
        case inertia
        case loiteringTime = "loitering_time"
    }
}

/// Zone filter configuration
struct ZoneFilterConfig: Codable, Hashable, Sendable {
    var minScore: Double?
    var minArea: Int?
    var maxArea: Int?
    var threshold: Double?

    enum CodingKeys: String, CodingKey {
        case minScore = "min_score"
        case minArea = "min_area"
        case maxArea = "max_area"
        case threshold
    }
}

/// Object detection configuration
struct ObjectConfig: Codable, Hashable, Sendable {
    var track: [String]?
    var filters: [String: ObjectFilterConfig]?
    var mask: [String]?

    init(track: [String]? = nil, filters: [String: ObjectFilterConfig]? = nil, mask: [String]? = nil) {
        self.track = track
        self.filters = filters
        self.mask = mask
    }
}

/// Object filter configuration
struct ObjectFilterConfig: Codable, Hashable, Sendable {
    var minScore: Double?
    var minArea: Int?
    var maxArea: Int?
    var threshold: Double?
    var mask: [String]?

    enum CodingKeys: String, CodingKey {
        case minScore = "min_score"
        case minArea = "min_area"
        case maxArea = "max_area"
        case threshold
        case mask
    }
}

/// FFmpeg input configuration
struct FFmpegInput: Codable, Hashable, Sendable {
    var path: String
    var roles: [String]
    var inputArgs: String?

    enum CodingKeys: String, CodingKey {
        case path
        case roles
        case inputArgs = "input_args"
    }
}

/// Camera status information (typically updated via MQTT)
struct CameraStatus: Codable, Hashable, Sendable {
    var recording: Bool
    var detecting: Bool
    var motionDetected: Bool
    var cameraFps: Double
    var detectionFps: Double
    var processFps: Double
    var skippedFps: Double
    var lastActivity: Date?

    init(
        recording: Bool = false,
        detecting: Bool = false,
        motionDetected: Bool = false,
        cameraFps: Double = 0,
        detectionFps: Double = 0,
        processFps: Double = 0,
        skippedFps: Double = 0,
        lastActivity: Date? = nil
    ) {
        self.recording = recording
        self.detecting = detecting
        self.motionDetected = motionDetected
        self.cameraFps = cameraFps
        self.detectionFps = detectionFps
        self.processFps = processFps
        self.skippedFps = skippedFps
        self.lastActivity = lastActivity
    }

    enum CodingKeys: String, CodingKey {
        case recording
        case detecting
        case motionDetected = "motion_detected"
        case cameraFps = "camera_fps"
        case detectionFps = "detection_fps"
        case processFps = "process_fps"
        case skippedFps = "skipped_fps"
        case lastActivity = "last_activity"
    }
}

// MARK: - Sample Data for Previews

extension Camera {
    static let sample = Camera(
        id: "front_door",
        name: "Front Door",
        streamURL: URL(string: "rtsp://192.168.1.100:8554/front_door"),
        snapshotURL: URL(string: "http://192.168.1.100:5000/api/front_door/latest.jpg"),
        config: CameraConfig(
            detect: DetectionConfig(enabled: true, width: 1280, height: 720, fps: 5),
            record: RecordConfig(enabled: true, retainDays: 7)
        ),
        status: CameraStatus(recording: true, detecting: true, cameraFps: 15.0, detectionFps: 5.0)
    )

    static let samples: [Camera] = [
        Camera(id: "front_door", name: "Front Door", status: CameraStatus(recording: true, detecting: true, cameraFps: 15.0)),
        Camera(id: "back_yard", name: "Back Yard", status: CameraStatus(recording: true, detecting: true, cameraFps: 20.0)),
        Camera(id: "garage", name: "Garage", status: CameraStatus(recording: false, detecting: true, cameraFps: 10.0)),
        Camera(id: "driveway", name: "Driveway", status: CameraStatus(recording: true, detecting: true, cameraFps: 25.0))
    ]
}
