import SwiftUI

/// Debug and statistics view for server monitoring.
struct DebugView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRefreshing = false
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?

    var body: some View {
        List {
            // Server info
            if let stats = appState.serverStats {
                // Service section
                if let service = stats.service {
                    Section("Service") {
                        if let version = service.version {
                            LabeledContent("Version", value: version)
                        }
                        if let latestVersion = service.latestVersion {
                            LabeledContent("Latest Version", value: latestVersion)
                        }
                        if let uptime = service.uptime {
                            LabeledContent("Uptime", value: formatUptime(uptime))
                        }
                    }
                }

                // Storage section
                if let storage = appState.serverStats?.service?.storage {
                    Section("Storage") {
                        ForEach(Array(storage.keys.sorted()), id: \.self) { path in
                            if let info = storage[path] {
                                StorageRow(path: path, storage: info)
                            }
                        }
                    }
                }

                // Detectors section
                if let detectors = stats.detectors {
                    Section("Detectors") {
                        ForEach(Array(detectors.keys.sorted()), id: \.self) { name in
                            if let detector = detectors[name] {
                                DetectorStatsRow(name: name, stats: detector)
                            }
                        }
                    }
                }

                // GPU section
                if let gpuUsages = stats.gpuUsages, !gpuUsages.isEmpty {
                    Section("GPU") {
                        ForEach(Array(gpuUsages.keys.sorted()), id: \.self) { name in
                            if let gpu = gpuUsages[name] {
                                GPUStatsRow(name: name, stats: gpu)
                            }
                        }
                    }
                }

                // Camera stats section
                if let cameras = stats.cameras {
                    Section("Camera Statistics") {
                        ForEach(Array(cameras.keys.sorted()), id: \.self) { name in
                            if let camera = cameras[name] {
                                CameraStatsRow(name: name, stats: camera)
                            }
                        }
                    }
                }

                // CPU section
                if let cpuUsages = stats.cpuUsages, !cpuUsages.isEmpty {
                    Section("CPU Usage") {
                        ForEach(Array(cpuUsages.keys.sorted()), id: \.self) { process in
                            if let usage = cpuUsages[process] {
                                LabeledContent(process, value: String(format: "%.1f%%", usage))
                            }
                        }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Statistics",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Unable to fetch server statistics")
                    )
                }
            }

            // Connection status section
            Section("Connection Status") {
                LabeledContent("API") {
                    ConnectionStatusBadge(status: appState.apiConnectionStatus)
                }
                LabeledContent("MQTT") {
                    ConnectionStatusBadge(status: appState.mqttConnectionStatus)
                }
            }
        }
        .navigationTitle("Debug & Stats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Toggle("Auto", isOn: $autoRefresh)
                        .toggleStyle(.button)
                        .onChange(of: autoRefresh) { _, newValue in
                            if newValue {
                                startAutoRefresh()
                            } else {
                                stopAutoRefresh()
                            }
                        }

                    Button {
                        refreshStats()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                }
            }
        }
        .refreshable {
            await appState.refreshStats()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            refreshStats()
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshStats() {
        isRefreshing = true
        Task {
            await appState.refreshStats()
            isRefreshing = false
        }
    }

    // MARK: - Helpers

    private func formatUptime(_ seconds: Double) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Storage Row

struct StorageRow: View {
    let path: String
    let storage: StorageStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(path)
                .font(.headline)

            if let percentage = storage.usedPercentage {
                ProgressView(value: percentage, total: 100)
                    .tint(percentage > 90 ? .red : percentage > 70 ? .orange : .blue)
            }

            HStack {
                Text("Used: \(storage.usedFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Free: \(storage.freeFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Total: \(storage.totalFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detector Stats Row

struct DetectorStatsRow: View {
    let name: String
    let stats: DetectorStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)

            HStack(spacing: 16) {
                if let speed = stats.inference_speed {
                    VStack(alignment: .leading) {
                        Text(String(format: "%.1f ms", speed))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Inference")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let pid = stats.pid {
                    VStack(alignment: .leading) {
                        Text("\(pid)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("PID")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - GPU Stats Row

struct GPUStatsRow: View {
    let name: String
    let stats: GPUStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)

            HStack(spacing: 16) {
                if let gpu = stats.gpu {
                    StatBadge(title: "GPU", value: gpu)
                }
                if let mem = stats.mem {
                    StatBadge(title: "Memory", value: mem)
                }
                if let encoder = stats.encoder {
                    StatBadge(title: "Encoder", value: encoder)
                }
                if let decoder = stats.decoder {
                    StatBadge(title: "Decoder", value: decoder)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Camera Stats Row

struct CameraStatsRow: View {
    let name: String
    let stats: CameraStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.headline)

                Spacer()

                if stats.detection_enabled == true {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            HStack(spacing: 12) {
                if let cameraFps = stats.camera_fps {
                    VStack {
                        Text(String(format: "%.1f", cameraFps))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Camera")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let detectionFps = stats.detection_fps {
                    VStack {
                        Text(String(format: "%.1f", detectionFps))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Detection")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let processFps = stats.process_fps {
                    VStack {
                        Text(String(format: "%.1f", processFps))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Process")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let skippedFps = stats.skipped_fps, skippedFps > 0 {
                    VStack {
                        Text(String(format: "%.1f", skippedFps))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                        Text("Skipped")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }
}

// MARK: - Connection Status Badge

struct ConnectionStatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.displayName)
                .font(.subheadline)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

#Preview {
    NavigationStack {
        DebugView()
            .environmentObject(AppState())
    }
}
