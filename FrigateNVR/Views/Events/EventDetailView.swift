import SwiftUI
import AVKit

/// Detailed view for a single event with snapshot, clip playback, and actions.
struct EventDetailView: View {
    let event: Event
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var snapshotImage: UIImage?
    @State private var isLoadingSnapshot = true
    @State private var showingClipPlayer = false
    @State private var showingDeleteConfirmation = false
    @State private var isRetained: Bool

    init(event: Event) {
        self.event = event
        _isRetained = State(initialValue: event.isRetained)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Snapshot/Clip viewer
                mediaSection

                // Event details
                detailsSection

                // Zones
                if !event.zones.isEmpty {
                    zonesSection
                }

                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            "Delete Event",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteEvent(event.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the event and associated media.")
        }
        .fullScreenCover(isPresented: $showingClipPlayer) {
            ClipPlayerView(event: event)
        }
        .task {
            await loadSnapshot()
        }
    }

    // MARK: - Media Section

    private var mediaSection: some View {
        ZStack {
            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(12)
                    .overlay {
                        if isLoadingSnapshot {
                            ProgressView()
                        } else {
                            Image(systemName: "photo.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                    }
            }

            // Play button for clips
            if event.hasClip {
                Button {
                    showingClipPlayer = true
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                }
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(spacing: 12) {
            // Label and confidence
            HStack {
                VStack(alignment: .leading) {
                    Text(event.label.capitalized)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let subLabel = event.subLabel {
                        Text(subLabel)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Confidence meter
                VStack(alignment: .trailing) {
                    Text("\(Int(event.topScore * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(confidenceColor)

                    Text("Confidence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Time and duration
            HStack(spacing: 16) {
                DetailItem(
                    icon: "clock",
                    title: "Start Time",
                    value: event.startTime.formatted(date: .abbreviated, time: .shortened)
                )

                if let duration = event.duration {
                    DetailItem(
                        icon: "timer",
                        title: "Duration",
                        value: event.durationString
                    )
                }
            }

            // Camera
            DetailItem(
                icon: "video",
                title: "Camera",
                value: event.cameraName
            )

            // Media availability
            HStack(spacing: 16) {
                MediaBadge(
                    icon: "photo.fill",
                    title: "Snapshot",
                    available: event.hasSnapshot
                )

                MediaBadge(
                    icon: "video.fill",
                    title: "Clip",
                    available: event.hasClip
                )
            }
        }
    }

    // MARK: - Zones Section

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zones")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(event.zones, id: \.self) { zone in
                    Text(zone)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Retain toggle
            Toggle(isOn: $isRetained) {
                Label("Retain Indefinitely", systemImage: "pin.fill")
            }
            .onChange(of: isRetained) { _, newValue in
                Task {
                    if newValue {
                        await appState.retainEvent(event.id)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // View clip button
            if event.hasClip {
                Button {
                    showingClipPlayer = true
                } label: {
                    Label("Watch Clip", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            // Delete button
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Event", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private var confidenceColor: Color {
        if event.topScore >= 0.9 { return .green }
        if event.topScore >= 0.7 { return .orange }
        return .red
    }

    private func loadSnapshot() async {
        guard event.hasSnapshot else {
            isLoadingSnapshot = false
            return
        }

        // Would fetch from API using event.snapshotURL(baseURL:)
        isLoadingSnapshot = false
    }
}

// MARK: - Detail Item

struct DetailItem: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Media Badge

struct MediaBadge: View {
    let icon: String
    let title: String
    let available: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(available ? .green : .gray)

            Text(title)
                .font(.subheadline)

            Spacer()

            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(available ? .green : .gray)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }

            size = CGSize(width: width, height: y + maxHeight)
        }
    }
}

// MARK: - Clip Player View

struct ClipPlayerView: View {
    let event: Event
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            // Would create player from event.clipURL(baseURL:)
        }
        .onDisappear {
            player?.pause()
        }
    }
}

#Preview {
    NavigationStack {
        EventDetailView(event: .sample)
            .environmentObject(AppState())
    }
}
