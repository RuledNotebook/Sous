import Foundation

/// Lets at most `limit` jobs run at once. Waiting jobs are admitted lowest priority number first (ties in
/// arrival order), and a waiting job can be moved to the front later with `raise`, which is how the step on
/// screen jumps the queue. A waiter whose task is cancelled is released without a slot (`acquire` returns false).
actor PriorityGate {
    private struct Waiter {
        let id: UUID
        var priority: Int
        let order: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var running = 0
    private var waiters: [Waiter] = []
    private var nextOrder = 0

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// True once the job holds a slot; false if it was cancelled while waiting. Call `release` after true.
    func acquire(id: UUID, priority: Int) async -> Bool {
        if Task.isCancelled { return false }
        if running < limit, waiters.isEmpty {
            running += 1
            return true
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiters.append(Waiter(id: id, priority: priority, order: nextOrder, continuation: continuation))
                nextOrder += 1
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        running = max(0, running - 1)
        admitNext()
    }

    /// Moves a waiting job ahead of everything else.
    func raise(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let front = (waiters.map(\.priority).min() ?? 0) - 1
        waiters[index].priority = front
    }

    var waitingCount: Int { waiters.count }
    var runningCount: Int { running }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func admitNext() {
        guard running < limit, !waiters.isEmpty else { return }
        let index = waiters.indices.min { a, b in
            (waiters[a].priority, waiters[a].order) < (waiters[b].priority, waiters[b].order)
        }!
        let waiter = waiters.remove(at: index)
        running += 1
        waiter.continuation.resume(returning: true)
    }
}
