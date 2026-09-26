import Foundation

/// Lets the microphone know when the app itself is talking, so read-aloud can never
/// trigger a command ("Next, add the garlic" must not skip a step). The speaker raises
/// the flag; the voice control ignores everything heard while it's up and for a short
/// grace period after, then starts a fresh recognition task.
nonisolated final class ReadAloudGate: @unchecked Sendable {
    static let shared = ReadAloudGate()

    /// How long after speech ends the mic keeps ignoring input (echo tails, late partials).
    let grace: TimeInterval = 0.8

    private let lock = NSLock()
    private var speaking = false
    private var endedAt = Date.distantPast
    private var observers: [@MainActor (Bool) -> Void] = []

    var isSpeaking: Bool { lock.withLock { speaking } }

    /// True while speaking and during the grace period after.
    func shouldIgnoreInput(at date: Date = .now) -> Bool {
        lock.withLock { speaking || date < endedAt.addingTimeInterval(grace) }
    }

    /// Called on the main actor when speech starts (true) and ends (false).
    func onChange(_ handler: @escaping @MainActor (Bool) -> Void) {
        lock.withLock { observers.append(handler) }
    }

    func speechDidStart() { set(speaking: true) }
    func speechDidEnd()   { set(speaking: false) }

    private func set(speaking now: Bool) {
        let handlers: [@MainActor (Bool) -> Void] = lock.withLock {
            guard speaking != now else { return [] }
            speaking = now
            if !now { endedAt = .now }
            return observers
        }
        for handler in handlers { Task { @MainActor in handler(now) } }
    }
}
