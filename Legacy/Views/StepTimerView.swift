import SwiftUI

/// Butter-yellow ring: the one loud element on screen, because it's the one
/// thing you need to see from across the kitchen. One ring per running timer.
struct StepTimerView: View {
    @Environment(CookSession.self) private var session
    let timer: StepTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            let progress = timer.length > 0 ? 1 - remaining / timer.length : 1
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.butter.opacity(0.25), lineWidth: 7)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.butter, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                        .font(.callout.weight(.bold))
                        .monospacedDigit()
                }
                .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 4) {
                    Text(remaining == 0 ? "Time's up" : "Timer running")
                        .font(.headline)
                    Text(timer.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Stop timer", role: .cancel) { session.stopTimer(timer.id) }
                        .font(.subheadline)
                }
                Spacer()
            }
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
    }
}
