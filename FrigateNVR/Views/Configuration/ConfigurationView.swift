import SwiftUI

/// Configuration editor for Frigate server settings.
struct ConfigurationView: View {
    @EnvironmentObject var appState: AppState
    @State private var rawConfig: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showingRawEditor = false
    @State private var errorMessage: String?
    @State private var showingSaveConfirmation = false
    @State private var showingRestartConfirmation = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading configuration...")
            } else if let config = appState.frigateConfig {
                configurationEditor(config)
            } else {
                ContentUnavailableView(
                    "Configuration Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Unable to load server configuration")
                )
            }
        }
        .navigationTitle("Configuration")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingRawEditor = true
                    } label: {
                        Label("Edit Raw YAML", systemImage: "doc.text")
                    }

                    Divider()

                    Button {
                        Task { await appState.refreshConfig() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        showingRestartConfirmation = true
                    } label: {
                        Label("Restart Frigate", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingRawEditor) {
            RawConfigEditorView(config: rawConfig)
        }
        .alert("Restart Frigate?", isPresented: $showingRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) {
                Task {
                    try? await appState.restartFrigate()
                }
            }
        } message: {
            Text("This will restart the Frigate service. All streams will be temporarily interrupted.")
        }
        .task {
            await loadConfiguration()
        }
    }

    // MARK: - Configuration Editor

    @ViewBuilder
    private func configurationEditor(_ config: FrigateConfig) -> some View {
        List {
            // MQTT Section
            Section("MQTT") {
                if let mqtt = config.mqtt {
                    LabeledContent("Host", value: mqtt.host ?? "Not configured")
                    LabeledContent("Port", value: String(mqtt.port ?? 1883))
                    LabeledContent("Enabled", value: mqtt.enabled == true ? "Yes" : "No")
                    if let prefix = mqtt.topicPrefix {
                        LabeledContent("Topic Prefix", value: prefix)
                    }
                } else {
                    Text("MQTT not configured")
                        .foregroundColor(.secondary)
                }
            }

            // Detectors Section
            Section("Detectors") {
                if let detectors = config.detectors {
                    ForEach(Array(detectors.keys.sorted()), id: \.self) { name in
                        if let detector = detectors[name] {
                            DetectorRow(name: name, detector: detector)
                        }
                    }
                } else {
                    Text("No detectors configured")
                        .foregroundColor(.secondary)
                }
            }

            // Cameras Section
            Section("Cameras") {
                if let cameras = config.cameras {
                    ForEach(Array(cameras.keys.sorted()), id: \.self) { name in
                        NavigationLink {
                            CameraConfigView(name: name, config: cameras[name]!)
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if cameras[name]?.enabled == false {
                                    Text("Disabled")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text("No cameras configured")
                        .foregroundColor(.secondary)
                }
            }

            // Global Detection Settings
            if let detect = config.detect {
                Section("Global Detection") {
                    LabeledContent("Enabled", value: detect.enabled == true ? "Yes" : "No")
                    if let width = detect.width, let height = detect.height {
                        LabeledContent("Resolution", value: "\(width)x\(height)")
                    }
                    if let fps = detect.fps {
                        LabeledContent("FPS", value: String(fps))
                    }
                }
            }

            // Global Recording Settings
            if let record = config.record {
                Section("Global Recording") {
                    LabeledContent("Enabled", value: record.enabled ? "Yes" : "No")
                    if let days = record.retainDays {
                        LabeledContent("Retain Days", value: String(days))
                    }
                }
            }

            // Birdseye
            if let birdseye = config.birdseye {
                Section("Birdseye") {
                    LabeledContent("Enabled", value: birdseye.enabled == true ? "Yes" : "No")
                    if let width = birdseye.width, let height = birdseye.height {
                        LabeledContent("Resolution", value: "\(width)x\(height)")
                    }
                    if let mode = birdseye.mode {
                        LabeledContent("Mode", value: mode)
                    }
                }
            }

            // go2rtc
            if let go2rtc = config.go2rtc {
                Section("go2rtc") {
                    if let streams = go2rtc.streams {
                        LabeledContent("Streams", value: "\(streams.count)")
                    }
                    if let rtsp = go2rtc.rtsp?.listen {
                        LabeledContent("RTSP Listen", value: rtsp)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadConfiguration() async {
        isLoading = true
        await appState.refreshConfig()
        isLoading = false
    }
}

// MARK: - Detector Row

struct DetectorRow: View {
    let name: String
    let detector: DetectorConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)

            HStack(spacing: 12) {
                if let type = detector.type {
                    Label(type, systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let device = detector.device {
                    Label(device, systemImage: "memorychip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Camera Config View

struct CameraConfigView: View {
    let name: String
    let config: CameraConfigFull

    var body: some View {
        List {
            Section("General") {
                LabeledContent("Enabled", value: config.enabled != false ? "Yes" : "No")
            }

            // FFmpeg inputs
            if let ffmpeg = config.ffmpeg, let inputs = ffmpeg.inputs {
                Section("Streams") {
                    ForEach(inputs, id: \.path) { input in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(input.path)
                                .font(.caption)
                                .lineLimit(1)

                            Text(input.roles.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Detection
            if let detect = config.detect {
                Section("Detection") {
                    LabeledContent("Enabled", value: detect.enabled ? "Yes" : "No")
                    if let width = detect.width, let height = detect.height {
                        LabeledContent("Resolution", value: "\(width)x\(height)")
                    }
                    if let fps = detect.fps {
                        LabeledContent("FPS", value: String(fps))
                    }
                }
            }

            // Recording
            if let record = config.record {
                Section("Recording") {
                    LabeledContent("Enabled", value: record.enabled ? "Yes" : "No")
                    if let days = record.retainDays {
                        LabeledContent("Retain Days", value: String(days))
                    }
                }
            }

            // Snapshots
            if let snapshots = config.snapshots {
                Section("Snapshots") {
                    LabeledContent("Enabled", value: snapshots.enabled ? "Yes" : "No")
                    if let height = snapshots.height {
                        LabeledContent("Height", value: String(height))
                    }
                }
            }

            // Zones
            if let zones = config.zones, !zones.isEmpty {
                Section("Zones") {
                    ForEach(Array(zones.keys.sorted()), id: \.self) { zoneName in
                        if let zone = zones[zoneName] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(zoneName)
                                    .font(.headline)

                                if let objects = zone.objects {
                                    Text(objects.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            // Objects
            if let objects = config.objects {
                Section("Objects") {
                    if let track = objects.track {
                        LabeledContent("Tracked", value: track.joined(separator: ", "))
                    }
                }
            }

            // ONVIF
            if let onvif = config.onvif {
                Section("ONVIF/PTZ") {
                    if let host = onvif.host {
                        LabeledContent("Host", value: host)
                    }
                    if let port = onvif.port {
                        LabeledContent("Port", value: String(port))
                    }
                    if let autoTracking = onvif.autoTracking {
                        LabeledContent("Auto Tracking", value: autoTracking.enabled == true ? "Yes" : "No")
                    }
                }
            }
        }
        .navigationTitle(name)
    }
}

// MARK: - Raw Config Editor View

struct RawConfigEditorView: View {
    @State var config: String
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                }

                TextEditor(text: $config)
                    .font(.system(.caption, design: .monospaced))
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Raw Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConfiguration()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func saveConfiguration() {
        isSaving = true
        errorMessage = nil

        Task {
            // Would call API to save raw config
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        ConfigurationView()
            .environmentObject(AppState())
    }
}
