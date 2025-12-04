import SwiftUI

/// Root content view that provides adaptive navigation for iPhone and iPad.
/// Uses NavigationSplitView on iPad and TabView on iPhone for optimal UX.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serverManager: ServerConnectionManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if serverManager.hasConfiguredServers {
                if horizontalSizeClass == .regular {
                    // iPad: Use NavigationSplitView for better use of screen space
                    iPadNavigationView()
                } else {
                    // iPhone: Use TabView for easier one-handed navigation
                    iPhoneTabView()
                }
            } else {
                // No servers configured - show setup
                ServerSetupView()
            }
        }
        .preferredColorScheme(appState.prefersDarkMode ? .dark : nil)
    }

    @ViewBuilder
    private func iPadNavigationView() -> some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            CameraListView()
        } detail: {
            DashboardView()
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func iPhoneTabView() -> some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "square.grid.2x2")
            }
            .tag(AppTab.dashboard)

            NavigationStack {
                EventsView()
            }
            .tabItem {
                Label("Events", systemImage: "clock.arrow.circlepath")
            }
            .tag(AppTab.events)
            .badge(appState.unreadEventCount)

            NavigationStack {
                RecordingsView()
            }
            .tabItem {
                Label("Recordings", systemImage: "video")
            }
            .tag(AppTab.recordings)

            NavigationStack {
                DebugView()
            }
            .tabItem {
                Label("Debug", systemImage: "chart.bar")
            }
            .tag(AppTab.debug)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(AppTab.settings)
        }
    }
}

/// Sidebar view for iPad navigation
struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedSidebarItem) {
            Section("Views") {
                NavigationLink(value: SidebarItem.dashboard) {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }

                NavigationLink(value: SidebarItem.events) {
                    Label("Events", systemImage: "clock.arrow.circlepath")
                }
                .badge(appState.unreadEventCount)

                NavigationLink(value: SidebarItem.recordings) {
                    Label("Recordings", systemImage: "video")
                }
            }

            Section("Cameras") {
                ForEach(appState.cameras) { camera in
                    NavigationLink(value: SidebarItem.camera(camera.id)) {
                        Label(camera.name, systemImage: camera.isRecording ? "video.fill" : "video")
                    }
                }
            }

            Section("System") {
                NavigationLink(value: SidebarItem.debug) {
                    Label("Debug & Stats", systemImage: "chart.bar")
                }

                NavigationLink(value: SidebarItem.configuration) {
                    Label("Configuration", systemImage: "slider.horizontal.3")
                }

                NavigationLink(value: SidebarItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .navigationTitle("Frigate")
    }
}

/// Camera list view for NavigationSplitView content column
struct CameraListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.selectedSidebarItem {
            case .dashboard:
                DashboardView()
            case .events:
                EventsView()
            case .recordings:
                RecordingsView()
            case .camera(let id):
                if let camera = appState.cameras.first(where: { $0.id == id }) {
                    LiveCameraView(camera: camera)
                } else {
                    ContentUnavailableView("Camera Not Found", systemImage: "video.slash")
                }
            case .debug:
                DebugView()
            case .configuration:
                ConfigurationView()
            case .settings:
                SettingsView()
            case .none:
                ContentUnavailableView("Select an Item", systemImage: "sidebar.left", description: Text("Choose a view from the sidebar"))
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ServerConnectionManager())
}
