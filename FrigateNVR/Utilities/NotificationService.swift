import Foundation
import UserNotifications
import UIKit

/// Service for handling local push notifications for Frigate events.
/// Manages notification authorization, scheduling, and handling.
actor NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var isAuthorized = false

    // Notification settings
    private var enabledLabels: Set<String> = ["person", "car", "dog", "cat"]
    private var enabledCameras: Set<String> = []
    private var criticalAlertsEnabled: Bool = false

    // MARK: - Authorization

    /// Request notification authorization from the user
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional]
            isAuthorized = try await center.requestAuthorization(options: options)
            return isAuthorized
        } catch {
            print("Failed to request notification authorization: \(error)")
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Settings

    /// Update enabled labels for notifications
    func setEnabledLabels(_ labels: Set<String>) {
        enabledLabels = labels
    }

    /// Update enabled cameras for notifications
    func setEnabledCameras(_ cameras: Set<String>) {
        enabledCameras = cameras
    }

    /// Enable/disable critical alerts
    func setCriticalAlerts(enabled: Bool) {
        criticalAlertsEnabled = enabled
    }

    /// Check if notifications should be shown for an event
    private func shouldNotify(for event: Event) -> Bool {
        // Check if label is enabled
        guard enabledLabels.isEmpty || enabledLabels.contains(event.label.lowercased()) else {
            return false
        }

        // Check if camera is enabled (empty means all cameras)
        guard enabledCameras.isEmpty || enabledCameras.contains(event.cameraName) else {
            return false
        }

        return true
    }

    // MARK: - Scheduling

    /// Schedule a notification for a detected event
    func scheduleEventNotification(event: Event) async {
        guard isAuthorized else { return }
        guard shouldNotify(for: event) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(event.label.capitalized) Detected"
        content.body = "Camera: \(event.cameraName)"

        if !event.zones.isEmpty {
            content.body += " | Zone: \(event.zones.joined(separator: ", "))"
        }

        content.sound = .default
        content.categoryIdentifier = NotificationCategory.event.rawValue

        // Add event data for handling
        content.userInfo = [
            "eventId": event.id,
            "cameraName": event.cameraName,
            "label": event.label,
            "timestamp": event.startTime.timeIntervalSince1970
        ]

        // Add thumbnail if available
        if event.hasSnapshot {
            // Would attach thumbnail image here
        }

        // Create thread identifier for grouping by camera
        content.threadIdentifier = "camera-\(event.cameraName)"

        // Use event ID as identifier to prevent duplicates
        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    /// Schedule a notification for camera status change
    func scheduleCameraStatusNotification(camera: Camera, status: String) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Camera Status Change"
        content.body = "\(camera.name): \(status)"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.status.rawValue
        content.threadIdentifier = "camera-status"

        let request = UNNotificationRequest(
            identifier: "status-\(camera.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule status notification: \(error)")
        }
    }

    // MARK: - Management

    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        center.removeAllPendingNotificationRequests()
    }

    /// Remove all delivered notifications
    func removeAllDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
    }

    /// Remove notifications for a specific event
    func removeNotification(for eventId: String) {
        center.removeDeliveredNotifications(withIdentifiers: [eventId])
        center.removePendingNotificationRequests(withIdentifiers: [eventId])
    }

    /// Get count of delivered notifications
    func getDeliveredNotificationCount() async -> Int {
        let notifications = await center.deliveredNotifications()
        return notifications.count
    }

    // MARK: - Categories and Actions

    /// Register notification categories and actions
    func registerCategories() {
        // Event notification actions
        let viewAction = UNNotificationAction(
            identifier: NotificationAction.view.rawValue,
            title: "View",
            options: [.foreground]
        )

        let retainAction = UNNotificationAction(
            identifier: NotificationAction.retain.rawValue,
            title: "Retain",
            options: []
        )

        let deleteAction = UNNotificationAction(
            identifier: NotificationAction.delete.rawValue,
            title: "Delete",
            options: [.destructive]
        )

        let eventCategory = UNNotificationCategory(
            identifier: NotificationCategory.event.rawValue,
            actions: [viewAction, retainAction, deleteAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Status notification category
        let statusCategory = UNNotificationCategory(
            identifier: NotificationCategory.status.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([eventCategory, statusCategory])
    }
}

// MARK: - Notification Categories

enum NotificationCategory: String {
    case event = "EVENT_NOTIFICATION"
    case status = "STATUS_NOTIFICATION"
}

// MARK: - Notification Actions

enum NotificationAction: String {
    case view = "VIEW_ACTION"
    case retain = "RETAIN_ACTION"
    case delete = "DELETE_ACTION"
}

// MARK: - Notification Handler

/// Handles notification responses when user interacts with notifications
@MainActor
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    weak var appState: AppState?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification banner even when app is in foreground
        return [.banner, .sound, .badge]
    }

    // Handle notification interaction
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        guard let eventId = userInfo["eventId"] as? String else { return }

        switch response.actionIdentifier {
        case NotificationAction.view.rawValue, UNNotificationDefaultActionIdentifier:
            // Navigate to event
            await handleViewAction(eventId: eventId)

        case NotificationAction.retain.rawValue:
            // Retain the event
            await handleRetainAction(eventId: eventId)

        case NotificationAction.delete.rawValue:
            // Delete the event
            await handleDeleteAction(eventId: eventId)

        default:
            break
        }
    }

    private func handleViewAction(eventId: String) async {
        // Find and present the event
        if let event = appState?.events.first(where: { $0.id == eventId }) {
            appState?.presentedEvent = event
            appState?.selectedTab = .events
        }
    }

    private func handleRetainAction(eventId: String) async {
        await appState?.retainEvent(eventId)
    }

    private func handleDeleteAction(eventId: String) async {
        await appState?.deleteEvent(eventId)
    }
}

// MARK: - Background Notification Support

/// Extension to handle background notification updates
extension NotificationService {
    /// Called when app receives a background notification
    func handleBackgroundNotification(userInfo: [AnyHashable: Any]) async {
        // Process background notification data
        // This would be called from AppDelegate's background notification handler
    }
}
