import Foundation
import UserNotifications
import os

/// One local notification per timer, so it fires from the background (or after a kill) too.
@MainActor
final class LocalTimerAlerts: TimerAlerts {
    private let center = UNUserNotificationCenter.current()
    private let presenter = ForegroundPresenter()
    private let log = Logger(subsystem: "com.cookalong.CookAlong", category: "timers")

    init() {
        center.delegate = presenter
    }

    /// Asks the first time a timer starts; later calls return the remembered answer at once.
    func requestAuthorization() async -> Bool {
        do { return try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { log.error("notification auth: \(error.localizedDescription, privacy: .public)"); return false }
    }

    func schedule(_ timer: StepTimer) async {
        log.info("requesting notification permission for '\(timer.title, privacy: .public)'")
        guard await requestAuthorization() else { log.notice("notifications not allowed; timer rings in-app only"); return }
        let content = UNMutableNotificationContent()
        content.title = "Time's up: \(timer.title)"
        content.body = "\(Int((timer.length / 60).rounded())) minutes are done. Say \"next\" when you're ready."
        content.sound = .default
        content.threadIdentifier = "cookalong.timers"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.remaining()), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: trigger))
            log.info("scheduled '\(timer.title, privacy: .public)' in \(Int(timer.remaining()))s")
        } catch {
            log.error("schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancel(_ id: StepTimer.ID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }
}

/// Show the banner and play the sound even while the app is in front.
nonisolated private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
