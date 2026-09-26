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

    var isSpeaking: Bool { lock.withLock { speaking } }

    /// True while speaking and during the grace period after.
    func shouldIgnoreInput(at date: Date = .now) -> Bool {
        lock.withLock { speaking || date < endedAt.addingTimeInterval(grace) }
    }

    func speechDidStart() { lock.withLock { speaking = true } }
    func speechDidEnd()   { lock.withLock { speaking = false; endedAt = .now } }
}
