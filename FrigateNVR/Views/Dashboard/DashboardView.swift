import SwiftUI

/// Main dashboard view displaying a grid of camera previews with live status.
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedCamera: Camera?
    @State private var isRefreshing = false

    private var columns: [GridItem] {
        let columnCount = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Connection status banner
                if appState.apiConnectionStatus != .connected {
                    ConnectionStatusBanner(
                        apiStatus: appState.apiConnectionStatus,
                        mqttStatus: appState.mqttConnectionStatus
                    )
                }

                // Quick stats
                QuickStatsView(cameras: appState.cameras, events: appState.events)
                    .padding(.horizontal)

                // Camera grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(appState.cameras) { camera in
                        CameraGridCell(camera: camera)
                            .onTapGesture {
                                selectedCamera = camera
                            }
                            .contextMenu {
                                cameraContextMenu(for: camera)
                            }
                    }
                }
                .padding(.horizontal)

                // Recent events
                RecentEventsSection(events: Array(appState.events.prefix(5)))
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isRefreshing = true
                        await appState.refreshAll()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
            }
        }
        .refreshable {
            await appState.refreshAll()
        }
        .sheet(item: $selectedCamera) { camera in
            NavigationStack {
                LiveCameraView(camera: camera)
            }
        }
        .alert(item: Binding(
            get: { appState.lastError },
            set: { _ in appState.clearError() }
        )) { error in
            Alert(
                title: Text("Error"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func cameraContextMenu(for camera: Camera) -> some View {
        Button {
            Task { await appState.toggleRecording(for: camera.id) }
        } label: {
            Label(
                camera.isRecording ? "Stop Recording" : "Start Recording",
                systemImage: camera.isRecording ? "record.circle.fill" : "record.circle"
            )
        }

        Button {
            Task { await appState.toggleDetection(for: camera.id) }
        } label: {
            Label(
                camera.isDetecting ? "Disable Detection" : "Enable Detection",
                systemImage: camera.isDetecting ? "eye.slash" : "eye"
            )
        }

        Divider()

        Button {
            selectedCamera = camera
        } label: {
            Label("View Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
        }
    }
}

// MARK: - Camera Grid Cell

struct CameraGridCell: View {
    let camera: Camera
    @State private var snapshotImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Camera preview
            ZStack {
                if let image = snapshotImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "video.slash")
                                    .foregroundColor(.gray)
                            }
                        }
                }

                // Status indicators overlay
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            if camera.isRecording {
                                Image(systemName: "record.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            if camera.isDetecting {
                                Image(systemName: "eye.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            if camera.status.motionDetected {
                                Image(systemName: "figure.walk.motion")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                        .padding(6)
                    }
                    Spacer()
                }
            }
            .cornerRadius(12)

            // Camera info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(camera.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(camera.isOnline ? Color.green : Color.red)
                            .frame(width: 6, height: 6)

                        Text(camera.isOnline ? "Online" : "Offline")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if camera.isOnline {
                            Text("\(Int(camera.status.cameraFps)) fps")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .task {
            await loadSnapshot()
        }
    }

    private func loadSnapshot() async {
        guard let url = camera.snapshotURL else {
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                snapshotImage = image
            }
        } catch {
            // Silently fail - camera might be offline
        }
        isLoading = false
    }
}

// MARK: - Connection Status Banner

struct ConnectionStatusBanner: View {
    let apiStatus: ConnectionStatus
    let mqttStatus: ConnectionStatus

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Issue")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("API: \(apiStatus.displayName) | MQTT: \(mqttStatus.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Quick Stats View

struct QuickStatsView: View {
    let cameras: [Camera]
    let events: [Event]

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Cameras",
                value: "\(cameras.count)",
                subtitle: "\(cameras.filter { $0.isOnline }.count) online",
                icon: "video.fill",
                color: .blue
            )

            StatCard(
                title: "Recording",
                value: "\(cameras.filter { $0.isRecording }.count)",
                subtitle: "cameras",
                icon: "record.circle.fill",
                color: .red
            )

            StatCard(
                title: "Events",
                value: "\(events.count)",
                subtitle: "today",
                icon: "clock.arrow.circlepath",
                color: .orange
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Recent Events Section

struct RecentEventsSection: View {
    let events: [Event]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Events")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: EventsView()) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }

            if events.isEmpty {
                Text("No recent events")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(events) { event in
                    EventRowCompact(event: event)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct EventRowCompact: View {
    let event: Event

    var body: some View {
        HStack(spacing: 12) {
            // Event icon
            Image(systemName: iconForLabel(event.label))
                .font(.title3)
                .foregroundColor(colorForLabel(event.label))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.label.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(event.cameraName) \(Text("").font(.caption))\(event.zones.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(event.startTime, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func iconForLabel(_ label: String) -> String {
        switch label.lowercased() {
        case "person": return "person.fill"
        case "car": return "car.fill"
        case "dog": return "dog.fill"
        case "cat": return "cat.fill"
        case "bird": return "bird.fill"
        case "motorcycle": return "bicycle"
        case "truck": return "box.truck.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private func colorForLabel(_ label: String) -> Color {
        switch label.lowercased() {
        case "person": return .blue
        case "car": return .orange
        case "dog": return .brown
        case "cat": return .purple
        default: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
            .environmentObject(AppState())
    }
}
