import SwiftUI

/// Settings view for app preferences and server management.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serverManager: ServerConnectionManager
    @State private var showingAddServer = false
    @State private var editingServer: ServerConnection?
    @State private var showingAbout = false

    var body: some View {
        Form {
            // Servers section
            Section {
                ForEach(serverManager.servers) { server in
                    ServerRow(server: server)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingServer = server
                        }
                        .swipeActions(edge: .trailing) {
                            if !server.isDefault {
                                Button(role: .destructive) {
                                    serverManager.deleteServer(server)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            Button {
                                serverManager.setDefaultServer(server)
                            } label: {
                                Label("Set Default", systemImage: "star")
                            }
                            .tint(.orange)
                        }
                }

                Button {
                    showingAddServer = true
                } label: {
                    Label("Add Server", systemImage: "plus.circle")
                }
            } header: {
                Text("Servers")
            } footer: {
                Text("Manage your Frigate NVR server connections")
            }

            // Appearance section
            Section("Appearance") {
                Toggle("Dark Mode", isOn: $appState.prefersDarkMode)
                    .onChange(of: appState.prefersDarkMode) { _, _ in
                        appState.saveUserPreferences()
                    }

                Toggle("Show Detection Overlays", isOn: $appState.showsDetectionOverlays)
                    .onChange(of: appState.showsDetectionOverlays) { _, _ in
                        appState.saveUserPreferences()
                    }
            }

            // Notifications section
            Section("Notifications") {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notification Settings", systemImage: "bell.badge")
                }
            }

            // Streaming section
            Section("Streaming") {
                NavigationLink {
                    StreamingSettingsView()
                } label: {
                    Label("Streaming Settings", systemImage: "video")
                }
            }

            // About section
            Section("About") {
                Button {
                    showingAbout = true
                } label: {
                    HStack {
                        Label("About Frigate NVR", systemImage: "info.circle")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)

                Link(destination: URL(string: "https://docs.frigate.video")!) {
                    Label("Frigate Documentation", systemImage: "book")
                }

                Link(destination: URL(string: "https://github.com/blakeblackshear/frigate")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
            }

            // Debug section
            Section("Debug") {
                NavigationLink {
                    DebugView()
                } label: {
                    Label("Server Statistics", systemImage: "chart.bar")
                }

                NavigationLink {
                    ConfigurationView()
                } label: {
                    Label("Configuration Editor", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingAddServer) {
            ServerFormView(mode: .add)
        }
        .sheet(item: $editingServer) { server in
            ServerFormView(mode: .edit(server))
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
}

// MARK: - Server Row

struct ServerRow: View {
    let server: ServerConnection

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(server.name)
                        .font(.headline)

                    if server.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }
                }

                Text(server.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Connection status
            Image(systemName: server.connectionStatus.systemImage)
                .foregroundColor(statusColor)
        }
    }

    private var statusColor: Color {
        switch server.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Server Form View

struct ServerFormView: View {
    enum Mode {
        case add
        case edit(ServerConnection)
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var serverManager: ServerConnectionManager

    @State private var formData: ServerFormData
    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _formData = State(initialValue: ServerFormData())
        case .edit(let server):
            _formData = State(initialValue: ServerFormData(from: server))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $formData.name)
                    TextField("URL (e.g., http://192.168.1.100:5000)", text: $formData.baseURLString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("API Key (optional)", text: $formData.apiKey)
                        .autocapitalization(.none)
                }

                Section("MQTT (Optional)") {
                    TextField("MQTT Host", text: $formData.mqttHost)
                        .autocapitalization(.none)
                    TextField("MQTT Port", text: $formData.mqttPort)
                        .keyboardType(.numberPad)
                    TextField("Username (optional)", text: $formData.mqttUsername)
                        .autocapitalization(.none)
                    SecureField("Password (optional)", text: $formData.mqttPassword)
                    Toggle("Use TLS", isOn: $formData.mqttUseTLS)
                    TextField("Topic Prefix", text: $formData.mqttTopicPrefix)
                        .autocapitalization(.none)
                }

                Section {
                    Toggle("Set as Default", isOn: $formData.isDefault)
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting || !formData.isValid)

                    if let result = testResult {
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                            VStack(alignment: .leading) {
                                Text(result.message)
                                    .font(.subheadline)
                                if let version = result.serverVersion {
                                    Text("Frigate \(version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let cameras = result.cameraCount {
                                    Text("\(cameras) cameras")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveServer()
                    }
                    .disabled(!formData.isValid)
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func testConnection() {
        guard let server = formData.toServerConnection() else { return }

        isTesting = true
        testResult = nil

        Task {
            testResult = await serverManager.testConnection(to: server)
            isTesting = false
        }
    }

    private func saveServer() {
        switch mode {
        case .add:
            if let server = formData.toServerConnection() {
                serverManager.addServer(server)
            }
        case .edit(let existing):
            if let server = formData.toServerConnection(existingId: existing.id) {
                serverManager.updateServer(server)
            }
        }
        dismiss()
    }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @State private var notificationsEnabled = true
    @State private var selectedLabels: Set<String> = ["person", "car"]
    @State private var criticalAlertsEnabled = false

    let availableLabels = ["person", "car", "dog", "cat", "bird", "motorcycle", "truck"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
            }

            Section("Object Types") {
                ForEach(availableLabels, id: \.self) { label in
                    Toggle(label.capitalized, isOn: Binding(
                        get: { selectedLabels.contains(label) },
                        set: { if $0 { selectedLabels.insert(label) } else { selectedLabels.remove(label) } }
                    ))
                }
            }

            Section {
                Toggle("Critical Alerts", isOn: $criticalAlertsEnabled)
            } footer: {
                Text("Critical alerts will play a sound even when Do Not Disturb is enabled")
            }
        }
        .navigationTitle("Notifications")
    }
}

// MARK: - Streaming Settings View

struct StreamingSettingsView: View {
    @State private var preferredProtocol = StreamProtocol.hls
    @State private var autoReconnect = true
    @State private var lowLatencyMode = true
    @State private var maxReconnectAttempts = 5

    var body: some View {
        Form {
            Section("Protocol") {
                Picker("Preferred Protocol", selection: $preferredProtocol) {
                    ForEach(StreamProtocol.allCases) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
            }

            Section("Connection") {
                Toggle("Auto Reconnect", isOn: $autoReconnect)
                Toggle("Low Latency Mode", isOn: $lowLatencyMode)

                Stepper("Max Reconnect Attempts: \(maxReconnectAttempts)", value: $maxReconnectAttempts, in: 1...10)
            }
        }
        .navigationTitle("Streaming")
    }
}

enum StreamProtocol: String, CaseIterable, Identifiable {
    case rtsp
    case hls
    case webrtc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rtsp: return "RTSP (Low Latency)"
        case .hls: return "HLS (HTTP Live Streaming)"
        case .webrtc: return "WebRTC"
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "video.badge.checkmark")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)

                VStack(spacing: 8) {
                    Text("Frigate NVR")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Mobile Client for iOS & iPadOS")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                VStack(spacing: 16) {
                    Text("A full-featured mobile client for self-hosted Frigate NVR servers. Monitor your cameras, review events, and manage your system from anywhere.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .navigationTitle("About")
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

// MARK: - Server Setup View

struct ServerSetupView: View {
    @State private var showingAddServer = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "video.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to Frigate NVR")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Add a Frigate server to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showingAddServer = true
            } label: {
                Label("Add Server", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showingAddServer) {
            ServerFormView(mode: .add)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AppState())
            .environmentObject(ServerConnectionManager())
    }
}
