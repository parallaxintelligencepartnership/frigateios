import Foundation
import AVFoundation
import Combine

/// Service for handling RTSP video streaming from Frigate cameras.
/// Provides low-latency live video streaming using native iOS media frameworks.
@MainActor
final class RTSPStreamService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var streamStatus: StreamStatus = .idle
    @Published private(set) var currentFPS: Double = 0
    @Published private(set) var bitrate: Double = 0
    @Published private(set) var latency: TimeInterval = 0
    @Published private(set) var lastError: StreamError?

    // MARK: - Player

    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?

    // MARK: - Stream Configuration

    private var currentURL: URL?
    private var reconnectTask: Task<Void, Never>?
    private var statsTimer: Timer?

    // Configuration
    var autoReconnect: Bool = true
    var maxReconnectAttempts: Int = 5
    var reconnectDelay: TimeInterval = 2.0

    private var reconnectAttempts: Int = 0

    // MARK: - Initialization

    init() {}

    deinit {
        stopStream()
    }

    // MARK: - Stream Control

    /// Start streaming from an RTSP URL
    func startStream(url: URL) {
        stopStream()

        currentURL = url
        streamStatus = .connecting
        reconnectAttempts = 0

        // Create player with RTSP URL
        // Note: AVPlayer supports RTSP natively on iOS
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [:],
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])

        playerItem = AVPlayerItem(asset: asset)
        playerItem?.preferredForwardBufferDuration = 1.0 // Minimize buffering for low latency

        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = false // Prioritize low latency

        setupObservers()

        player?.play()
        isStreaming = true
    }

    /// Start streaming from a camera
    func startStream(camera: Camera) {
        guard let streamURL = camera.streamURL else {
            lastError = .invalidURL
            streamStatus = .error
            return
        }
        startStream(url: streamURL)
    }

    /// Start streaming using HLS from go2rtc
    func startHLSStream(baseURL: URL, cameraId: String) {
        let hlsURL = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent(cameraId)
            .appendingPathComponent("stream.m3u8")
        startStream(url: hlsURL)
    }

    /// Start streaming using WebRTC (would require additional implementation)
    func startWebRTCStream(baseURL: URL, cameraId: String) async throws {
        // WebRTC implementation would go here
        // This would involve setting up a WebRTC peer connection
        throw StreamError.unsupportedProtocol
    }

    /// Stop the current stream
    func stopStream() {
        reconnectTask?.cancel()
        reconnectTask = nil

        statsTimer?.invalidate()
        statsTimer = nil

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        bufferObserver?.invalidate()
        bufferObserver = nil

        player?.pause()
        player = nil
        playerItem = nil

        isStreaming = false
        streamStatus = .idle
        currentURL = nil
        reconnectAttempts = 0
    }

    /// Pause the stream
    func pause() {
        player?.pause()
        streamStatus = .paused
    }

    /// Resume the stream
    func resume() {
        player?.play()
        if streamStatus == .paused {
            streamStatus = .playing
        }
    }

    /// Seek to live edge (for HLS streams)
    func seekToLive() {
        guard let duration = playerItem?.duration, duration.isNumeric else { return }
        let livePosition = CMTime(seconds: duration.seconds - 1, preferredTimescale: 1)
        player?.seek(to: livePosition)
    }

    // MARK: - Observer Setup

    private func setupObservers() {
        // Observe player item status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleStatusChange(item.status)
            }
        }

        // Observe buffer state
        bufferObserver = playerItem?.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    if self?.streamStatus == .buffering {
                        self?.streamStatus = .playing
                    }
                }
            }
        }

        // Add periodic time observer for stats
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateStats()
        }

        // Setup stats timer
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStats()
            }
        }
    }

    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            streamStatus = .playing
            reconnectAttempts = 0
            lastError = nil

        case .failed:
            streamStatus = .error
            lastError = .playbackFailed(playerItem?.error?.localizedDescription ?? "Unknown error")
            attemptReconnect()

        case .unknown:
            streamStatus = .buffering

        @unknown default:
            break
        }
    }

    private func updateStats() {
        guard let item = playerItem else { return }

        // Calculate approximate latency
        if let accessLog = item.accessLog(),
           let lastEvent = accessLog.events.last {
            bitrate = lastEvent.observedBitrate
            latency = lastEvent.startupTime
        }

        // Estimate FPS from video track
        if let videoTrack = item.asset.tracks(withMediaType: .video).first {
            currentFPS = Double(videoTrack.nominalFrameRate)
        }
    }

    // MARK: - Reconnection

    private func attemptReconnect() {
        guard autoReconnect,
              reconnectAttempts < maxReconnectAttempts,
              let url = currentURL else {
            streamStatus = .error
            return
        }

        reconnectAttempts += 1
        streamStatus = .reconnecting

        reconnectTask = Task {
            let delay = reconnectDelay * Double(reconnectAttempts)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            startStream(url: url)
        }
    }

    // MARK: - Snapshot

    /// Capture a snapshot from the current stream
    func captureSnapshot() async throws -> CGImage {
        guard let player = player,
              let currentItem = player.currentItem else {
            throw StreamError.noActiveStream
        }

        let asset = currentItem.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        let time = player.currentTime()

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, error in
                if let error = error {
                    continuation.resume(throwing: StreamError.snapshotFailed(error.localizedDescription))
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: StreamError.snapshotFailed("No image generated"))
                }
            }
        }
    }
}

// MARK: - Stream Status

enum StreamStatus: String, Sendable {
    case idle
    case connecting
    case buffering
    case playing
    case paused
    case reconnecting
    case error

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting..."
        case .buffering: return "Buffering..."
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .reconnecting: return "Reconnecting..."
        case .error: return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "video.slash"
        case .connecting: return "wifi"
        case .buffering: return "hourglass"
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        case .reconnecting: return "arrow.clockwise"
        case .error: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Stream Error

enum StreamError: LocalizedError {
    case invalidURL
    case connectionFailed(String)
    case playbackFailed(String)
    case noActiveStream
    case snapshotFailed(String)
    case unsupportedProtocol
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid stream URL"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .playbackFailed(let message):
            return "Playback failed: \(message)"
        case .noActiveStream:
            return "No active stream"
        case .snapshotFailed(let message):
            return "Snapshot failed: \(message)"
        case .unsupportedProtocol:
            return "Unsupported streaming protocol"
        case .timeout:
            return "Stream connection timed out"
        }
    }
}

// MARK: - Video Player View

import SwiftUI

/// SwiftUI view for displaying the video stream
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

import AVKit

/// Native SwiftUI video player wrapper with overlay support
struct StreamPlayerView: View {
    @ObservedObject var streamService: RTSPStreamService
    let camera: Camera
    var showOverlay: Bool = true
    var showControls: Bool = true

    @State private var showingStats: Bool = false

    var body: some View {
        ZStack {
            // Video player
            if let player = streamService.player {
                VideoPlayer(player: player)
                    .disabled(!showControls)
            } else {
                // Placeholder when no stream
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: streamService.streamStatus.systemImage)
                                .font(.largeTitle)
                                .foregroundColor(.white)
                            Text(streamService.streamStatus.displayName)
                                .foregroundColor(.white)
                        }
                    }
            }

            // Status overlay
            if showOverlay {
                VStack {
                    HStack {
                        // Camera name
                        Text(camera.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)

                        Spacer()

                        // Stream stats
                        if showingStats {
                            HStack(spacing: 8) {
                                Label("\(Int(streamService.currentFPS)) fps", systemImage: "speedometer")
                                Label(formatBitrate(streamService.bitrate), systemImage: "arrow.down.circle")
                            }
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                        }

                        // Status indicator
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .padding(8)
                    }
                    .padding(8)

                    Spacer()

                    // Error message
                    if let error = streamService.lastError {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                            .padding()
                    }
                }
            }
        }
        .onTapGesture {
            if showControls {
                showingStats.toggle()
            }
        }
        .onAppear {
            if streamService.player == nil {
                streamService.startStream(camera: camera)
            }
        }
        .onDisappear {
            streamService.stopStream()
        }
    }

    private var statusColor: Color {
        switch streamService.streamStatus {
        case .playing: return .green
        case .buffering, .connecting, .reconnecting: return .yellow
        case .error: return .red
        case .idle, .paused: return .gray
        }
    }

    private func formatBitrate(_ bitrate: Double) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", bitrate / 1_000_000)
        } else if bitrate >= 1000 {
            return String(format: "%.0f Kbps", bitrate / 1000)
        } else {
            return String(format: "%.0f bps", bitrate)
        }
    }
}
