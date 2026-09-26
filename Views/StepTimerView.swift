import SwiftUI

/// Butter-yellow ring: the one loud element on screen, because it's the one
/// thing you need to see from across the kitchen.
struct StepTimerView: View {
    @Environment(CookSession.self) private var session
    let timer: CountdownTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            let progress = timer.progress(at: context.date)
            let clock = Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond))
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.timer.opacity(0.25), lineWidth: 7)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.timer, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(clock)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(10)
                }
                .frame(width: 84, height: 84)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(remaining == 0 ? "Timer finished" : "\(clock) remaining")

                VStack(alignment: .leading, spacing: 4) {
                    Text(remaining == 0 ? "Time's up" : "Timer running")
                        .font(.headline)
                    Text(timer.stepTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Stop timer", role: .cancel) { session.stopTimer() }
                        .font(.subheadline)
                        .frame(minHeight: 44, alignment: .leading)
                }
                Spacer()
            }
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
    }
}
