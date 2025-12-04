import SwiftUI
import AVKit

/// Full-screen live camera view with stream controls and detection overlays.
struct LiveCameraView: View {
    let camera: Camera

    @StateObject private var streamService = RTSPStreamService()
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showControls = true
    @State private var showSettings = false
    @State private var showOverlays = true
    @State private var isFullScreen = false
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                Color.black
                    .ignoresSafeArea()

                if let player = streamService.player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: isFullScreen ? .all : [])
                } else {
                    streamPlaceholder
                }

                // Detection overlays
                if showOverlays && appState.showsDetectionOverlays {
                    DetectionOverlayView(
                        events: appState.events.filter { $0.cameraName == camera.id },
                        frameSize: geometry.size
                    )
                }

                // Controls overlay
                if showControls && !isFullScreen {
                    controlsOverlay
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
                scheduleHideControls()
            }
        }
        .navigationTitle(camera.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isFullScreen {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle("Show Overlays", isOn: $showOverlays)

                        Button {
                            showSettings = true
                        } label: {
                            Label("Camera Settings", systemImage: "gear")
                        }

                        Divider()

                        Button {
                            Task {
                                await appState.toggleRecording(for: camera.id)
                            }
                        } label: {
                            Label(
                                camera.isRecording ? "Stop Recording" : "Start Recording",
                                systemImage: camera.isRecording ? "stop.circle" : "record.circle"
                            )
                        }

                        Button {
                            Task {
                                await appState.toggleDetection(for: camera.id)
                            }
                        } label: {
                            Label(
                                camera.isDetecting ? "Disable Detection" : "Enable Detection",
                                systemImage: camera.isDetecting ? "eye.slash" : "eye"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsSheet(camera: camera)
        }
        .onAppear {
            streamService.startStream(camera: camera)
            scheduleHideControls()
        }
        .onDisappear {
            streamService.stopStream()
            hideControlsTask?.cancel()
        }
        .statusBarHidden(isFullScreen)
    }

    // MARK: - Subviews

    private var streamPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: streamService.streamStatus.systemImage)
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.6))

            Text(streamService.streamStatus.displayName)
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))

            if let error = streamService.lastError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if streamService.streamStatus == .error {
                Button("Retry") {
                    streamService.startStream(camera: camera)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                // Camera status
                HStack(spacing: 8) {
                    Circle()
                        .fill(camera.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(camera.name)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

                Spacer()

                // Stream stats
                HStack(spacing: 12) {
                    if streamService.isStreaming {
                        Label("\(Int(streamService.currentFPS))", systemImage: "speedometer")
                        Label(formatBitrate(streamService.bitrate), systemImage: "arrow.down.circle")
                    }
                }
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .padding()

            Spacer()

            // Bottom controls
            HStack(spacing: 24) {
                // Recording indicator
                if camera.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("REC")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(6)
                }

                Spacer()

                // Playback controls
                HStack(spacing: 20) {
                    Button {
                        if streamService.streamStatus == .playing {
                            streamService.pause()
                        } else {
                            streamService.resume()
                        }
                    } label: {
                        Image(systemName: streamService.streamStatus == .playing ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Button {
                        Task {
                            if let snapshot = try? await streamService.captureSnapshot() {
                                // Save snapshot
                                let image = UIImage(cgImage: snapshot)
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            }
                        }
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Button {
                        withAnimation {
                            isFullScreen.toggle()
                        }
                    } label: {
                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)

                Spacer()

                // Detection indicator
                if camera.isDetecting {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.green)
                        Text("DETECT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.3))
                    .cornerRadius(6)
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }

    private func formatBitrate(_ bitrate: Double) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1fM", bitrate / 1_000_000)
        } else if bitrate >= 1000 {
            return String(format: "%.0fK", bitrate / 1000)
        } else {
            return String(format: "%.0f", bitrate)
        }
    }
}

// MARK: - Detection Overlay View

struct DetectionOverlayView: View {
    let events: [Event]
    let frameSize: CGSize

    var body: some View {
        Canvas { context, size in
            for event in events.filter({ $0.endTime == nil }) {
                guard let box = event.box else { continue }

                // Scale bounding box to frame size
                let rect = CGRect(
                    x: box.x1 * size.width,
                    y: box.y1 * size.height,
                    width: box.width * size.width,
                    height: box.height * size.height
                )

                // Draw bounding box
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.stroke(path, with: .color(colorForLabel(event.label)), lineWidth: 2)

                // Draw label
                let labelText = Text("\(event.label) \(Int(event.score * 100))%")
                    .font(.caption2)
                    .foregroundColor(.white)

                context.draw(
                    labelText,
                    at: CGPoint(x: rect.minX + 4, y: rect.minY - 8)
                )
            }
        }
    }

    private func colorForLabel(_ label: String) -> Color {
        switch label.lowercased() {
        case "person": return .blue
        case "car": return .orange
        case "dog": return .brown
        case "cat": return .purple
        default: return .green
        }
    }
}

// MARK: - Camera Settings Sheet

struct CameraSettingsSheet: View {
    let camera: Camera
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    Toggle("Recording Enabled", isOn: Binding(
                        get: { camera.isRecording },
                        set: { _ in Task { await appState.toggleRecording(for: camera.id) } }
                    ))

                    if let retainDays = camera.config.record.retainDays {
                        LabeledContent("Retain Days", value: "\(retainDays)")
                    }
                }

                Section("Detection") {
                    Toggle("Detection Enabled", isOn: Binding(
                        get: { camera.isDetecting },
                        set: { _ in Task { await appState.toggleDetection(for: camera.id) } }
                    ))

                    if let fps = camera.config.detect.fps {
                        LabeledContent("Detection FPS", value: "\(fps)")
                    }

                    if let width = camera.config.detect.width,
                       let height = camera.config.detect.height {
                        LabeledContent("Resolution", value: "\(width)x\(height)")
                    }
                }

                Section("Snapshots") {
                    Toggle("Snapshots Enabled", isOn: .constant(camera.config.snapshots.enabled))
                }

                Section("Zones") {
                    if camera.config.zones.isEmpty {
                        Text("No zones configured")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(camera.config.zones.keys.sorted()), id: \.self) { zoneName in
                            Text(zoneName)
                        }
                    }
                }

                Section("Statistics") {
                    LabeledContent("Camera FPS", value: String(format: "%.1f", camera.status.cameraFps))
                    LabeledContent("Detection FPS", value: String(format: "%.1f", camera.status.detectionFps))
                    LabeledContent("Process FPS", value: String(format: "%.1f", camera.status.processFps))
                    LabeledContent("Skipped FPS", value: String(format: "%.1f", camera.status.skippedFps))
                }
            }
            .navigationTitle(camera.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LiveCameraView(camera: .sample)
            .environmentObject(AppState())
    }
}
