import Testing
@testable import FrigateNVR

@Suite("FrigateNVR Tests")
struct FrigateNVRTests {

    @Test("Camera model initialization")
    func testCameraInit() {
        let camera = Camera(
            id: "test_camera",
            name: "Test Camera",
            config: CameraConfig(
                detect: DetectionConfig(enabled: true, width: 1280, height: 720, fps: 5),
                record: RecordConfig(enabled: true, retainDays: 7)
            ),
            status: CameraStatus(recording: true, detecting: true, cameraFps: 15.0)
        )

        #expect(camera.id == "test_camera")
        #expect(camera.name == "Test Camera")
        #expect(camera.isRecording == true)
        #expect(camera.isDetecting == true)
        #expect(camera.config.detect.fps == 5)
    }

    @Test("Event model initialization")
    func testEventInit() {
        let event = Event(
            id: "123456",
            cameraName: "front_door",
            label: "person",
            zones: ["front_yard"],
            startTime: Date(),
            endTime: Date().addingTimeInterval(30),
            score: 0.85,
            topScore: 0.92,
            hasSnapshot: true,
            hasClip: true
        )

        #expect(event.id == "123456")
        #expect(event.label == "person")
        #expect(event.zones.count == 1)
        #expect(event.hasSnapshot == true)
        #expect(event.duration == 30)
    }

    @Test("Event filter query parameters")
    func testEventFilterQueryParams() {
        var filter = EventFilter()
        filter.cameras = Set(["front_door", "back_yard"])
        filter.labels = Set(["person"])
        filter.limit = 100

        let params = filter.queryParameters()

        #expect(params.contains { $0.name == "limit" && $0.value == "100" })
        #expect(params.contains { $0.name == "labels" && $0.value == "person" })
    }

    @Test("Server connection initialization")
    func testServerConnectionInit() {
        let server = ServerConnection(
            name: "Home Frigate",
            baseURL: URL(string: "http://192.168.1.100:5000")!,
            mqttConfig: MQTTConfig(host: "192.168.1.100", port: 1883),
            isDefault: true
        )

        #expect(server.name == "Home Frigate")
        #expect(server.baseURL.absoluteString == "http://192.168.1.100:5000")
        #expect(server.isDefault == true)
        #expect(server.mqttConfig?.port == 1883)
    }

    @Test("MQTT config initialization with defaults")
    func testMQTTConfigDefaults() {
        let config = MQTTConfig(host: "localhost")

        #expect(config.host == "localhost")
        #expect(config.port == 1883)
        #expect(config.useTLS == false)
        #expect(config.topicPrefix == "frigate")
        #expect(config.keepAliveInterval == 60)
        #expect(config.cleanSession == true)
        #expect(config.autoReconnect == true)
    }

    @Test("Connection test result success")
    func testConnectionTestResultSuccess() {
        let result = ConnectionTestResult.success(
            latencyMs: 50,
            serverVersion: "0.13.0",
            cameraCount: 4
        )

        #expect(result.success == true)
        #expect(result.latencyMs == 50)
        #expect(result.serverVersion == "0.13.0")
        #expect(result.cameraCount == 4)
    }

    @Test("Connection test result failure")
    func testConnectionTestResultFailure() {
        let result = ConnectionTestResult.failure("Connection refused")

        #expect(result.success == false)
        #expect(result.message == "Connection refused")
        #expect(result.latencyMs == nil)
    }

    @Test("Server form data validation")
    func testServerFormDataValidation() {
        var formData = ServerFormData()

        // Invalid - empty name and URL
        #expect(formData.isValid == false)

        // Add name
        formData.name = "Test Server"
        #expect(formData.isValid == false)

        // Add valid URL
        formData.baseURLString = "http://192.168.1.100:5000"
        #expect(formData.isValid == true)

        // Invalid URL
        formData.baseURLString = "not a url"
        #expect(formData.isValid == false)
    }

    @Test("Bounding box calculations")
    func testBoundingBoxCalculations() {
        let box = BoundingBox(x1: 0.1, y1: 0.2, x2: 0.5, y2: 0.8)

        #expect(box.width == 0.4)
        #expect(box.height == 0.6)
        #expect(box.centerX == 0.3)
        #expect(box.centerY == 0.5)
    }

    @Test("Storage stats formatting")
    func testStorageStatsFormatting() {
        let storage = StorageStats(
            free: 50_000_000_000,
            mount_type: "ext4",
            total: 100_000_000_000,
            used: 50_000_000_000
        )

        #expect(storage.usedPercentage == 50.0)
    }
}

@Suite("API Service Tests")
struct APIServiceTests {

    @Test("API error descriptions")
    func testAPIErrorDescriptions() {
        let invalidURL = APIError.invalidURL
        #expect(invalidURL.errorDescription == "Invalid URL")

        let httpError = APIError.httpError(statusCode: 404, data: nil)
        #expect(httpError.errorDescription?.contains("404") == true)
    }
}

@Suite("Stream Service Tests")
struct StreamServiceTests {

    @Test("Stream status display names")
    func testStreamStatusDisplayNames() {
        #expect(StreamStatus.idle.displayName == "Idle")
        #expect(StreamStatus.connecting.displayName == "Connecting...")
        #expect(StreamStatus.playing.displayName == "Playing")
        #expect(StreamStatus.error.displayName == "Error")
    }

    @Test("Stream error descriptions")
    func testStreamErrorDescriptions() {
        let invalidURL = StreamError.invalidURL
        #expect(invalidURL.errorDescription == "Invalid stream URL")

        let timeout = StreamError.timeout
        #expect(timeout.errorDescription == "Stream connection timed out")
    }
}
