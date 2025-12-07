import SwiftUI
import AVKit

/// View for browsing and playing back continuous recordings.
struct RecordingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCamera: Camera?
    @State private var selectedDate: Date = Date()
    @State private var recordingSummaries: [RecordingSummary] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Camera selector
            cameraSelector

            // Date picker
            datePicker

            // Timeline or recordings list
            if let camera = selectedCamera {
                recordingsTimeline(for: camera)
            } else {
                ContentUnavailableView(
                    "Select a Camera",
                    systemImage: "video",
                    description: Text("Choose a camera to view recordings")
                )
            }
        }
        .navigationTitle("Recordings")
        .onAppear {
            if selectedCamera == nil {
                selectedCamera = appState.cameras.first
            }
        }
        .onChange(of: selectedCamera) { _, _ in
            Task { await loadRecordings() }
        }
        .onChange(of: selectedDate) { _, _ in
            Task { await loadRecordings() }
        }
    }

    // MARK: - Camera Selector

    private var cameraSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.cameras) { camera in
                    CameraPill(
                        camera: camera,
                        isSelected: selectedCamera?.id == camera.id
                    )
                    .onTapGesture {
                        selectedCamera = camera
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Date Picker

    private var datePicker: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            DatePicker(
                "",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()

            Spacer()

            Button {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                if tomorrow <= Date() {
                    selectedDate = tomorrow
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Recordings Timeline

    @ViewBuilder
    private func recordingsTimeline(for camera: Camera) -> some View {
        if isLoading {
            ProgressView("Loading recordings...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if recordingSummaries.isEmpty {
            ContentUnavailableView(
                "No Recordings",
                systemImage: "video.slash",
                description: Text("No recordings available for this date")
            )
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary card
                    RecordingSummaryCard(summaries: recordingSummaries)

                    // Hourly breakdown
                    ForEach(recordingSummaries.flatMap { $0.hours }, id: \.hour) { hour in
                        HourlyRecordingRow(hour: hour, cameraId: camera.id, date: selectedDate)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Data Loading

    private func loadRecordings() async {
        guard let camera = selectedCamera else { return }

        isLoading = true
        defer { isLoading = false }

        // Would fetch from API
        // let summaries = try? await apiService.fetchRecordingSummary(cameraId: camera.id)
        recordingSummaries = []
    }
}

// MARK: - Camera Pill

struct CameraPill: View {
    let camera: Camera
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(camera.isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)

            Text(camera.name)
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemBackground))
        .foregroundColor(isSelected ? .accentColor : .primary)
        .cornerRadius(20)
    }
}

// MARK: - Recording Summary Card

struct RecordingSummaryCard: View {
    let summaries: [RecordingSummary]

    private var totalEvents: Int {
        summaries.reduce(0) { $0 + $1.events }
    }

    private var totalDuration: TimeInterval {
        summaries.flatMap { $0.hours }.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        HStack(spacing: 24) {
            VStack {
                Text("\(totalEvents)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 40)

            VStack {
                Text(formatDuration(totalDuration))
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 40)

            VStack {
                Text("\(summaries.flatMap { $0.hours }.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Hours")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Hourly Recording Row

struct HourlyRecordingRow: View {
    let hour: HourSummary
    let cameraId: String
    let date: Date
    @State private var showingPlayer = false

    var body: some View {
        Button {
            showingPlayer = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hour.hour)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label("\(hour.events)", systemImage: "clock.arrow.circlepath")
                        Label("\(hour.motion)", systemImage: "figure.walk.motion")
                        Label("\(hour.objects)", systemImage: "square.dashed")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Text(formatDuration(hour.duration))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showingPlayer) {
            RecordingPlayerView(cameraId: cameraId, date: date, hour: hour.hour)
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Player View

struct RecordingPlayerView: View {
    let cameraId: String
    let date: Date
    let hour: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading recording...")
                        .foregroundColor(.white)
                }
            }

            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(cameraId)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("\(date.formatted(date: .abbreviated, time: .omitted)) - \(hour)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
                .padding()

                Spacer()
            }
        }
        .onAppear {
            // Would create player from VOD URL
        }
        .onDisappear {
            player?.pause()
        }
    }
}

#Preview {
    NavigationStack {
        RecordingsView()
            .environmentObject(AppState())
    }
}
