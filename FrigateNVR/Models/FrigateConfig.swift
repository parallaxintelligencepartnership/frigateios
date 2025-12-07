import Foundation

/// Represents the complete Frigate NVR configuration.
/// This maps to the YAML configuration file used by Frigate.
struct FrigateConfig: Codable, Sendable {
    var mqtt: MQTTServerConfig?
    var database: DatabaseConfig?
    var detectors: [String: DetectorConfig]?
    var model: ModelConfig?
    var loggers: [String: LoggerConfig]?
    var birdseye: BirdseyeConfig?
    var ffmpeg: FFmpegGlobalConfig?
    var detect: GlobalDetectConfig?
    var objects: GlobalObjectConfig?
    var motion: MotionConfig?
    var record: RecordConfig?
    var snapshots: SnapshotConfig?
    var live: LiveConfig?
    var go2rtc: Go2RTCConfig?
    var cameras: [String: CameraConfigFull]?
    var timestamp: TimestampConfig?
    var ui: UIConfig?

    /// Get a camera configuration by name
    func getCamera(_ name: String) -> CameraConfigFull? {
        cameras?[name]
    }

    /// Get all camera names
    var cameraNames: [String] {
        cameras?.keys.sorted() ?? []
    }
}

/// MQTT server configuration for Frigate
struct MQTTServerConfig: Codable, Sendable {
    var enabled: Bool?
    var host: String?
    var port: Int?
    var user: String?
    var password: String?
    var topicPrefix: String?
    var clientId: String?
    var stats_interval: Int?

    enum CodingKeys: String, CodingKey {
        case enabled
        case host
        case port
        case user
        case password
        case topicPrefix = "topic_prefix"
        case clientId = "client_id"
        case stats_interval
    }
}

/// Database configuration
struct DatabaseConfig: Codable, Sendable {
    var path: String?
}

/// Detector configuration (e.g., coral, cpu, gpu)
struct DetectorConfig: Codable, Sendable {
    var type: String?
    var device: String?
    var numThreads: Int?
    var model: ModelConfig?

    enum CodingKeys: String, CodingKey {
        case type
        case device
        case numThreads = "num_threads"
        case model
    }
}

/// Model configuration for object detection
struct ModelConfig: Codable, Sendable {
    var path: String?
    var labelmap_path: String?
    var width: Int?
    var height: Int?
    var input_tensor: String?
    var input_pixel_format: String?
    var labelmap: [String: String]?
}

/// Logger configuration
struct LoggerConfig: Codable, Sendable {
    var level: String?
}

/// Birdseye view configuration
struct BirdseyeConfig: Codable, Sendable {
    var enabled: Bool?
    var restream: Bool?
    var width: Int?
    var height: Int?
    var quality: Int?
    var mode: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case restream
        case width
        case height
        case quality
        case mode
    }
}

/// Global FFmpeg configuration
struct FFmpegGlobalConfig: Codable, Sendable {
    var globalArgs: [String]?
    var hwaccel_args: String?
    var input_args: String?
    var output_args: FFmpegOutputArgs?
    var retry_interval: Double?

    enum CodingKeys: String, CodingKey {
        case globalArgs = "global_args"
        case hwaccel_args
        case input_args
        case output_args
        case retry_interval
    }
}

/// FFmpeg output arguments
struct FFmpegOutputArgs: Codable, Sendable {
    var detect: [String]?
    var record: String?
    var rtmp: String?
}

/// Global detection configuration
struct GlobalDetectConfig: Codable, Sendable {
    var enabled: Bool?
    var width: Int?
    var height: Int?
    var fps: Int?
    var maxDisappeared: Int?
    var stationary: StationaryConfig?

    enum CodingKeys: String, CodingKey {
        case enabled
        case width
        case height
        case fps
        case maxDisappeared = "max_disappeared"
        case stationary
    }
}

/// Global object detection configuration
struct GlobalObjectConfig: Codable, Sendable {
    var track: [String]?
    var filters: [String: ObjectFilterConfig]?
    var mask: [String]?
}

/// Live streaming configuration
struct LiveConfig: Codable, Sendable {
    var stream_name: String?
    var height: Int?
    var quality: Int?
}

/// go2rtc configuration
struct Go2RTCConfig: Codable, Sendable {
    var streams: [String: [String]]?
    var rtsp: RTSPServerConfig?
    var webrtc: WebRTCConfig?
}

/// RTSP server configuration
struct RTSPServerConfig: Codable, Sendable {
    var listen: String?
    var username: String?
    var password: String?
}

/// WebRTC configuration
struct WebRTCConfig: Codable, Sendable {
    var candidates: [String]?
}

/// Full camera configuration
struct CameraConfigFull: Codable, Sendable {
    var enabled: Bool?
    var ffmpeg: CameraFFmpegConfig?
    var detect: DetectionConfig?
    var record: RecordConfig?
    var snapshots: SnapshotConfig?
    var motion: MotionConfig?
    var objects: ObjectConfig?
    var zones: [String: ZoneConfig]?
    var live: LiveConfig?
    var ui: CameraUIConfig?
    var onvif: ONVIFConfig?
    var timestamp: TimestampConfig?
    var mqtt: CameraMQTTConfig?
    var birdseye: CameraBirdseyeConfig?
}

/// Camera-specific FFmpeg configuration
struct CameraFFmpegConfig: Codable, Sendable {
    var inputs: [FFmpegInput]?
    var globalArgs: [String]?
    var hwaccelArgs: String?
    var inputArgs: String?
    var outputArgs: FFmpegOutputArgs?
    var retryInterval: Double?

    enum CodingKeys: String, CodingKey {
        case inputs
        case globalArgs = "global_args"
        case hwaccelArgs = "hwaccel_args"
        case inputArgs = "input_args"
        case outputArgs = "output_args"
        case retryInterval = "retry_interval"
    }
}

/// Camera UI configuration
struct CameraUIConfig: Codable, Sendable {
    var order: Int?
    var dashboard: Bool?
}

/// ONVIF configuration for PTZ cameras
struct ONVIFConfig: Codable, Sendable {
    var host: String?
    var port: Int?
    var user: String?
    var password: String?
    var autoTracking: AutoTrackingConfig?

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case user
        case password
        case autoTracking = "autotracking"
    }
}

/// Auto-tracking configuration
struct AutoTrackingConfig: Codable, Sendable {
    var enabled: Bool?
    var calibrate_on_startup: Bool?
    var zooming: String?
    var zoom_factor: Double?
    var track: [String]?
    var required_zones: [String]?
    var timeout: Int?
}

/// Timestamp overlay configuration
struct TimestampConfig: Codable, Sendable {
    var style: TimestampStyle?
    var format: String?
    var position: String?
    var color: TimestampColor?
    var thickness: Int?
    var effect: String?
}

/// Timestamp style configuration
struct TimestampStyle: Codable, Sendable {
    var position: String?
    var format: String?
    var color: TimestampColor?
    var thickness: Int?
    var effect: String?
}

/// Timestamp color configuration
struct TimestampColor: Codable, Sendable {
    var red: Int?
    var green: Int?
    var blue: Int?
}

/// Camera-specific MQTT configuration
struct CameraMQTTConfig: Codable, Sendable {
    var enabled: Bool?
    var timestamp: Bool?
    var boundingBox: Bool?
    var crop: Bool?
    var height: Int?
    var quality: Int?
    var requiredZones: [String]?

    enum CodingKeys: String, CodingKey {
        case enabled
        case timestamp
        case boundingBox = "bounding_box"
        case crop
        case height
        case quality
        case requiredZones = "required_zones"
    }
}

/// Camera-specific birdseye configuration
struct CameraBirdseyeConfig: Codable, Sendable {
    var enabled: Bool?
    var mode: String?
    var order: Int?
}

/// UI configuration
struct UIConfig: Codable, Sendable {
    var live_mode: String?
    var use_experimental: Bool?
    var timezone: String?
    var time_format: String?
    var date_style: String?
    var time_style: String?
    var strftime_fmt: String?
}

// MARK: - Server Statistics

/// Server statistics and health information
struct ServerStats: Codable, Sendable {
    var service: ServiceStats?
    var detectors: [String: DetectorStats]?
    var gpuUsages: [String: GPUStats]?
    var cpuUsages: [String: Double]?
    var cameras: [String: CameraStats]?

    enum CodingKeys: String, CodingKey {
        case service
        case detectors
        case gpuUsages = "gpu_usages"
        case cpuUsages = "cpu_usages"
        case cameras
    }
}

/// Service-level statistics
struct ServiceStats: Codable, Sendable {
    var uptime: Double?
    var version: String?
    var latestVersion: String?
    var storage: [String: StorageStats]?

    enum CodingKeys: String, CodingKey {
        case uptime
        case version
        case latestVersion = "latest_version"
        case storage
    }
}

/// Storage statistics
struct StorageStats: Codable, Sendable {
    var free: Double?
    var mount_type: String?
    var total: Double?
    var used: Double?

    var usedPercentage: Double? {
        guard let used, let total, total > 0 else { return nil }
        return (used / total) * 100
    }

    var freeFormatted: String {
        guard let free else { return "N/A" }
        return ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
    }

    var usedFormatted: String {
        guard let used else { return "N/A" }
        return ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .file)
    }

    var totalFormatted: String {
        guard let total else { return "N/A" }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }
}

/// Detector statistics
struct DetectorStats: Codable, Sendable {
    var detection_start: Double?
    var inference_speed: Double?
    var pid: Int?

    enum CodingKeys: String, CodingKey {
        case detection_start
        case inference_speed
        case pid
    }
}

/// GPU usage statistics
struct GPUStats: Codable, Sendable {
    var gpu: String?
    var mem: String?
    var encoder: String?
    var decoder: String?
}

/// Camera-level statistics
struct CameraStats: Codable, Sendable {
    var camera_fps: Double?
    var detection_fps: Double?
    var capture_pid: Int?
    var ffmpeg_pid: Int?
    var pid: Int?
    var process_fps: Double?
    var skipped_fps: Double?
    var detection_enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case camera_fps
        case detection_fps
        case capture_pid
        case ffmpeg_pid
        case pid
        case process_fps
        case skipped_fps
        case detection_enabled
    }
}

// MARK: - Recording Data

/// Recording segment information
struct RecordingSegment: Identifiable, Codable, Sendable {
    var id: String { "\(camera)-\(startTime)" }
    let camera: String
    let startTime: Double
    let endTime: Double
    let duration: Double
    let motionCount: Int?
    let objectCount: Int?

    var startDate: Date {
        Date(timeIntervalSince1970: startTime)
    }

    var endDate: Date {
        Date(timeIntervalSince1970: endTime)
    }

    enum CodingKeys: String, CodingKey {
        case camera
        case startTime = "start_time"
        case endTime = "end_time"
        case duration
        case motionCount = "motion"
        case objectCount = "objects"
    }
}

/// Recording summary for a day
struct RecordingSummary: Identifiable, Codable, Sendable {
    var id: String { "\(camera)-\(day)" }
    let camera: String
    let day: String
    let hours: [HourSummary]
    let events: Int

    var date: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }
}

/// Hourly summary within a recording day
struct HourSummary: Codable, Sendable {
    let hour: String
    let duration: Double
    let events: Int
    let motion: Int
    let objects: Int
}
