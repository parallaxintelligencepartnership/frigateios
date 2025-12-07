# Frigate NVR Mobile Client for iOS/iPadOS

A full-featured, high-performance mobile application for iOS and iPadOS (version 26+) that serves as a comprehensive client for self-hosted [Frigate NVR](https://frigate.video) servers.

## Features

### Core Functionality
- **Live Camera Streaming**: Low-latency RTSP/HLS video streaming with native AVPlayer integration
- **Multi-Camera Dashboard**: Grid view of all cameras with live status indicators
- **Event Review**: Browse, filter, and view clips and snapshots for all detected events
- **Real-Time Notifications**: Instant push notifications via MQTT for detected objects
- **Full Configuration Management**: Edit Frigate settings directly from your mobile device

### Camera Management
- View live feeds from multiple cameras simultaneously
- Full-screen single camera view with detection overlays
- Toggle recording, detection, and motion tracking per camera
- Access camera statistics (FPS, detection rates)

### Event Management
- Chronological event feed with search and filtering
- Filter by object type (person, car, dog, etc.)
- Filter by camera, zone, and time range
- View event snapshots and video clips
- Retain or delete events
- Mark events for indefinite retention

### Recording Playback
- Browse continuous recordings by camera and date
- Hourly breakdown with event counts
- Direct playback of recorded footage

### Server Administration
- Multi-server support with easy switching
- Connection testing and status monitoring
- Debug statistics (CPU, GPU, storage, detector performance)
- Raw configuration YAML editing
- Service restart capability

## Architecture

### Communication Layers

The app uses three distinct protocols to communicate with Frigate:

| Protocol | Purpose | Implementation |
|----------|---------|----------------|
| **REST API** | Configuration, events, clips | URLSession with async/await |
| **MQTT** | Real-time events, status | CocoaMQTT with persistent connection |
| **RTSP/HLS** | Live video streaming | AVPlayer with native decoding |

### Project Structure

```
FrigateNVR/
├── App/                    # App entry point and root views
├── Models/                 # Data models (Camera, Event, Config, etc.)
├── Services/
│   ├── API/               # REST API service layer
│   ├── MQTT/              # MQTT client and message handling
│   └── RTSP/              # Video streaming service
├── ViewModels/            # View model layer (if needed)
├── Views/
│   ├── Dashboard/         # Main camera grid
│   ├── LiveView/          # Full-screen camera view
│   ├── Events/            # Event timeline and details
│   ├── Settings/          # App and server settings
│   ├── Configuration/     # Frigate config editor
│   ├── Debug/             # Statistics and debugging
│   └── Components/        # Reusable UI components
├── Utilities/             # Extensions and helpers
└── Resources/             # Assets and localization
```

## Requirements

- iOS 26.0+ / iPadOS 26.0+
- Xcode 16.0+
- Swift 6.0+
- A running Frigate NVR server (v0.13+)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/frigateios.git
   cd frigateios
   ```

2. Open in Xcode:
   ```bash
   open FrigateNVR.xcodeproj
   ```

   Or use Swift Package Manager:
   ```bash
   swift build
   ```

3. Configure signing and run on your device

## Configuration

### Server Setup

1. Launch the app
2. Tap "Add Server" on the welcome screen
3. Enter your Frigate server details:
   - **Name**: Friendly name for the server
   - **URL**: Full URL including port (e.g., `http://192.168.1.100:5000`)
   - **API Key**: Optional, if configured on your server

4. Optionally configure MQTT for real-time notifications:
   - **MQTT Host**: Broker hostname
   - **MQTT Port**: Default 1883
   - **Username/Password**: If authentication is required
   - **Topic Prefix**: Usually `frigate`

5. Tap "Test Connection" to verify
6. Save the configuration

### MQTT Configuration (Recommended)

For real-time notifications, ensure your Frigate server has MQTT configured:

```yaml
mqtt:
  enabled: true
  host: your-mqtt-broker
  port: 1883
  topic_prefix: frigate
```

## Usage

### Dashboard
The main dashboard shows a grid of all configured cameras with:
- Live snapshot previews (auto-refreshing)
- Recording status indicators
- Detection status indicators
- Quick access to recent events

Tap any camera to open full-screen live view.

### Live View
- Swipe or tap to show/hide controls
- Use the play/pause button to control streaming
- Capture screenshots directly to your photo library
- View real-time detection overlays
- Access camera settings via the menu

### Events
- Pull down to refresh
- Use the filter bar to narrow results
- Tap an event for full details
- Swipe left to delete or retain
- Access clips and snapshots

### Settings
- Manage multiple server connections
- Configure notification preferences
- Adjust streaming settings
- Access debug information

## Development

### Building

```bash
# Build the project
swift build

# Run tests
swift test

# Generate Xcode project (if using SPM)
swift package generate-xcodeproj
```

### Dependencies

- **CocoaMQTT**: MQTT 5.0 client for real-time messaging

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Frigate NVR](https://frigate.video) - The amazing open-source NVR this app connects to
- [CocoaMQTT](https://github.com/emqx/CocoaMQTT) - MQTT client library
- The Frigate community for inspiration and feedback

## Support

- [Frigate Documentation](https://docs.frigate.video)
- [GitHub Issues](https://github.com/your-org/frigateios/issues)
- [Frigate Discord](https://discord.gg/frigate)
