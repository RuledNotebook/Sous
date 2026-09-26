import Foundation
import UIKit
import UserNotifications
import os

/// Local notifications for kitchen timers: one per timer (keyed by the step it belongs to), so
/// the pasta and the sauce can ring separately, from the background or after the app is killed.
///
/// Wiring: `TimerNotifications.shared.schedule(timer)` when a timer starts,
/// `TimerNotifications.shared.cancel(stepID:)` when it is stopped or dismissed.
@MainActor
final class TimerNotifications {
    static let shared = TimerNotifications()

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

    func schedule(_ timer: CountdownTimer) async {
        let id = Self.identifier(for: timer.stepID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        log.info("requesting notification permission for '\(timer.stepTitle, privacy: .public)'")
        guard await requestAuthorization() else { log.notice("notifications not allowed; timer rings in-app only"); return }
        let content = UNMutableNotificationContent()
        content.title = "Time's up: \(timer.stepTitle)"
        content.body = "\(Int((timer.length / 60).rounded())) minutes are done. Say \"next\" when you're ready."
        content.sound = .default
        content.threadIdentifier = "cookalong.timers"
        let remaining = max(1, timer.remaining(at: .now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            log.info("scheduled '\(timer.stepTitle, privacy: .public)' in \(Int(remaining))s")
        } catch {
            log.error("schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancel(stepID: RecipeStep.ID) {
        let id = Self.identifier(for: stepID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private static func identifier(for stepID: RecipeStep.ID) -> String { "cookalong.timer.\(stepID.uuidString)" }
}

/// Show the banner and play the sound even while the app is in front.
nonisolated private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// Keeps the screen on while a recipe is open. Call `KeepScreenAwake.set(true)` when a recipe
/// loads and `set(false)` when it closes.
@MainActor
enum KeepScreenAwake {
    static func set(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }
}
