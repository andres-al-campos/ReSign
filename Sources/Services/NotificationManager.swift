import UserNotifications
import Foundation

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var onRetry: ((UUID) -> Void)?
    var onCleanRetry: ((UUID) -> Void)?
    var onOpenXcode: (() -> Void)?
    var onOpenProject: ((UUID) -> Void)?

    /// De-duplication: we only want one signed-out notification visible at a
    /// time, no matter how many projects were due when we noticed.
    private static let signedOutNotificationID = "signed-out-xcode"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupCategories()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendFailureNotification(project: ManagedProject, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Build Failed — \(project.name)"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "BUILD_FAILURE"
        content.userInfo = ["projectID": project.id.uuidString]
        let request = UNNotificationRequest(
            identifier: "failure-\(project.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendProjectSigningNotification(project: ManagedProject, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Build Failed — \(project.name)"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "PROJECT_SIGNING"
        content.userInfo = ["projectID": project.id.uuidString]
        let request = UNNotificationRequest(
            identifier: "failure-\(project.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendStaleCacheNotification(project: ManagedProject, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Build Failed — \(project.name)"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "STALE_CACHE"
        content.userInfo = ["projectID": project.id.uuidString]
        let request = UNNotificationRequest(
            identifier: "failure-\(project.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendSuccessNotification(project: ManagedProject) {
        let content = UNMutableNotificationContent()
        content.title = "\(project.name) installed"
        content.body = "Provisioning profile renewed successfully."
        let request = UNNotificationRequest(
            identifier: "success-\(project.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendSignedOutNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Not signed in to Xcode"
        content.body = "Open Xcode → Settings → Accounts and sign in with your Apple ID; builds resume automatically once you're signed in."
        content.sound = .default
        content.categoryIdentifier = "SIGNED_OUT"
        let request = UNNotificationRequest(
            identifier: Self.signedOutNotificationID,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func clearSignedOutNotification() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.signedOutNotificationID])
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.signedOutNotificationID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        // A plain click on the notification body reports the default action; we
        // treat it as the category's primary action so the whole banner is a
        // clickable shortcut, not just the small button.
        let isBodyClick = action == UNNotificationDefaultActionIdentifier
        let projectID = (response.notification.request.content.userInfo["projectID"] as? String)
            .flatMap(UUID.init(uuidString:))

        // Signed-out: button or body-click opens Xcode.
        if action == "OPEN_XCODE" || (isBodyClick && category == "SIGNED_OUT") {
            Task { @MainActor in self.onOpenXcode?() }
            return
        }

        guard let projectID else { return }

        // Project-signing: button or body-click opens the project in Xcode.
        if action == "OPEN_PROJECT" || (isBodyClick && category == "PROJECT_SIGNING") {
            Task { @MainActor in self.onOpenProject?(projectID) }
            return
        }

        if action == "CLEAN_RETRY" {
            Task { @MainActor in self.onCleanRetry?(projectID) }
            return
        }

        if action == "RETRY_BUILD" {
            Task { @MainActor in self.onRetry?(projectID) }
        }
    }

    // MARK: - Private

    private func setupCategories() {
        let retryAction = UNNotificationAction(
            identifier: "RETRY_BUILD",
            title: "Retry",
            options: [.foreground]
        )
        let failureCategory = UNNotificationCategory(
            identifier: "BUILD_FAILURE",
            actions: [retryAction],
            intentIdentifiers: [],
            options: []
        )

        let openXcodeAction = UNNotificationAction(
            identifier: "OPEN_XCODE",
            title: "Open Xcode",
            options: [.foreground]
        )
        let signedOutCategory = UNNotificationCategory(
            identifier: "SIGNED_OUT",
            actions: [openXcodeAction],
            intentIdentifiers: [],
            options: []
        )

        let openProjectAction = UNNotificationAction(
            identifier: "OPEN_PROJECT",
            title: "Open Project in Xcode",
            options: [.foreground]
        )
        let projectSigningCategory = UNNotificationCategory(
            identifier: "PROJECT_SIGNING",
            actions: [openProjectAction],
            intentIdentifiers: [],
            options: []
        )

        let cleanRetryAction = UNNotificationAction(
            identifier: "CLEAN_RETRY",
            title: "Clean & Retry",
            options: [.foreground]
        )
        let staleCacheCategory = UNNotificationCategory(
            identifier: "STALE_CACHE",
            actions: [cleanRetryAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([failureCategory, signedOutCategory, projectSigningCategory, staleCacheCategory])
    }
}
