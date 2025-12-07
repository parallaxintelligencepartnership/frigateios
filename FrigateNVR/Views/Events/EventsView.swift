import SwiftUI

/// Events timeline view with filtering and search capabilities.
struct EventsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedFilter = EventFilterType.all
    @State private var selectedTimeRange = TimeRange.today
    @State private var selectedLabels: Set<String> = []
    @State private var selectedCameras: Set<String> = []
    @State private var showFilters = false
    @State private var selectedEvent: Event?

    private var filteredEvents: [Event] {
        var events = appState.events

        // Text search
        if !searchText.isEmpty {
            events = events.filter { event in
                event.label.localizedCaseInsensitiveContains(searchText) ||
                event.cameraName.localizedCaseInsensitiveContains(searchText) ||
                event.zones.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Filter type
        switch selectedFilter {
        case .all:
            break
        case .withClip:
            events = events.filter { $0.hasClip }
        case .withSnapshot:
            events = events.filter { $0.hasSnapshot }
        case .retained:
            events = events.filter { $0.isRetained }
        }

        // Label filter
        if !selectedLabels.isEmpty {
            events = events.filter { selectedLabels.contains($0.label.lowercased()) }
        }

        // Camera filter
        if !selectedCameras.isEmpty {
            events = events.filter { selectedCameras.contains($0.cameraName) }
        }

        // Time range
        let cutoffDate: Date? = {
            switch selectedTimeRange {
            case .today:
                return Calendar.current.startOfDay(for: Date())
            case .yesterday:
                return Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
            case .week:
                return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month:
                return Calendar.current.date(byAdding: .month, value: -1, to: Date())
            case .all:
                return nil
            }
        }()

        if let cutoffDate {
            events = events.filter { $0.startTime >= cutoffDate }
        }

        return events
    }

    private var groupedEvents: [(Date, [Event])] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
            Calendar.current.startOfDay(for: event.startTime)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            // Events list
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No events match your filters")
                )
            } else {
                eventsList
            }
        }
        .navigationTitle("Events")
        .searchable(text: $searchText, prompt: "Search events...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFilters.toggle()
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await appState.refreshEvents()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            EventFiltersSheet(
                selectedLabels: $selectedLabels,
                selectedCameras: $selectedCameras,
                availableLabels: availableLabels,
                availableCameras: appState.cameras.map { $0.name }
            )
        }
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                EventDetailView(event: event)
            }
        }
        .onAppear {
            appState.markEventsAsRead()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Filter type
                Menu {
                    ForEach(EventFilterType.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            HStack {
                                Text(filter.displayName)
                                if selectedFilter == filter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    FilterChip(
                        title: selectedFilter.displayName,
                        isActive: selectedFilter != .all
                    )
                }

                // Time range
                Menu {
                    ForEach(TimeRange.allCases) { range in
                        Button {
                            selectedTimeRange = range
                        } label: {
                            HStack {
                                Text(range.displayName)
                                if selectedTimeRange == range {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    FilterChip(
                        title: selectedTimeRange.displayName,
                        isActive: selectedTimeRange != .today
                    )
                }

                // Selected labels
                if !selectedLabels.isEmpty {
                    FilterChip(
                        title: "\(selectedLabels.count) Labels",
                        isActive: true
                    ) {
                        selectedLabels.removeAll()
                    }
                }

                // Selected cameras
                if !selectedCameras.isEmpty {
                    FilterChip(
                        title: "\(selectedCameras.count) Cameras",
                        isActive: true
                    ) {
                        selectedCameras.removeAll()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Events List

    private var eventsList: some View {
        List {
            ForEach(groupedEvents, id: \.0) { date, events in
                Section {
                    ForEach(events) { event in
                        EventRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEvent = event
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await appState.deleteEvent(event.id)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    Task {
                                        await appState.retainEvent(event.id)
                                    }
                                } label: {
                                    Label("Retain", systemImage: "pin")
                                }
                                .tint(.orange)
                            }
                    }
                } header: {
                    Text(date, style: .date)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await appState.refreshEvents()
        }
    }

    // MARK: - Helpers

    private var hasActiveFilters: Bool {
        selectedFilter != .all ||
        !selectedLabels.isEmpty ||
        !selectedCameras.isEmpty
    }

    private var availableLabels: [String] {
        Set(appState.events.map { $0.label.lowercased() }).sorted()
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: Event
    @State private var thumbnailImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: iconForLabel(event.label))
                                .foregroundColor(.gray)
                        }
                }
            }
            .frame(width: 80, height: 60)
            .cornerRadius(8)
            .clipped()

            // Event info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.label.capitalized)
                        .font(.headline)

                    if event.isRetained {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    // Confidence
                    Text("\(Int(event.topScore * 100))%")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(confidenceColor.opacity(0.2))
                        .foregroundColor(confidenceColor)
                        .cornerRadius(4)
                }

                Text(event.cameraName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    // Time
                    Label(event.startTime, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Duration
                    if let duration = event.duration {
                        Text(event.durationString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Media indicators
                    HStack(spacing: 4) {
                        if event.hasSnapshot {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if event.hasClip {
                            Image(systemName: "video")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Zones
                if !event.zones.isEmpty {
                    Text(event.zones.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var confidenceColor: Color {
        if event.topScore >= 0.9 { return .green }
        if event.topScore >= 0.7 { return .orange }
        return .red
    }

    private func iconForLabel(_ label: String) -> String {
        switch label.lowercased() {
        case "person": return "person.fill"
        case "car": return "car.fill"
        case "dog": return "dog.fill"
        case "cat": return "cat.fill"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var isActive: Bool = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline)

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
        .foregroundColor(isActive ? .accentColor : .primary)
        .cornerRadius(16)
    }
}

// MARK: - Event Filters Sheet

struct EventFiltersSheet: View {
    @Binding var selectedLabels: Set<String>
    @Binding var selectedCameras: Set<String>
    let availableLabels: [String]
    let availableCameras: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Labels") {
                    ForEach(availableLabels, id: \.self) { label in
                        Toggle(label.capitalized, isOn: Binding(
                            get: { selectedLabels.contains(label) },
                            set: { isSelected in
                                if isSelected {
                                    selectedLabels.insert(label)
                                } else {
                                    selectedLabels.remove(label)
                                }
                            }
                        ))
                    }
                }

                Section("Cameras") {
                    ForEach(availableCameras, id: \.self) { camera in
                        Toggle(camera, isOn: Binding(
                            get: { selectedCameras.contains(camera) },
                            set: { isSelected in
                                if isSelected {
                                    selectedCameras.insert(camera)
                                } else {
                                    selectedCameras.remove(camera)
                                }
                            }
                        ))
                    }
                }

                Section {
                    Button("Clear All Filters") {
                        selectedLabels.removeAll()
                        selectedCameras.removeAll()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
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

// MARK: - Filter Types

enum EventFilterType: String, CaseIterable, Identifiable {
    case all
    case withClip
    case withSnapshot
    case retained

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .withClip: return "With Clip"
        case .withSnapshot: return "With Snapshot"
        case .retained: return "Retained"
        }
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case week
    case month
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .week: return "This Week"
        case .month: return "This Month"
        case .all: return "All Time"
        }
    }
}

#Preview {
    NavigationStack {
        EventsView()
            .environmentObject(AppState())
    }
}
