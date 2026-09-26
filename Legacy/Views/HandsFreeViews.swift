import SwiftUI

/// Mic and read-aloud toggles, plus a banner you can read from across the kitchen
/// that says whether we're listening and what we last heard.
struct HandsFreeBar: View {
    @Environment(CookSession.self) private var session

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { session.voiceControlEnabled },
                                     set: { session.setVoiceControl($0) })) {
                    Label(session.voiceControlEnabled ? "Mic on" : "Mic off",
                          systemImage: session.voice.state.isListening ? "mic.fill" : "mic")
                }
                .toggleStyle(.button)
                .tint(session.voice.state.isListening ? .red : Theme.basil)
                .accessibilityLabel("Voice control")

                Toggle(isOn: $session.readAloud) {
                    Label("Read aloud", systemImage: session.readAloud ? "speaker.wave.2.fill" : "speaker.wave.2")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Read each step aloud")

                Spacer()
            }
            .font(.subheadline)

            if session.voiceControlEnabled {
                ListeningBanner(state: session.voice.state, heard: session.voice.heard,
                                lastCommand: session.voice.lastCommand, lastCommandAt: session.voice.lastCommandAt)
            }
        }
    }
}

private struct ListeningBanner: View {
    @Environment(\.openURL) private var openURL
    let state: VoiceControlState
    let heard: String
    let lastCommand: VoiceCommand?
    let lastCommandAt: Date?

    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case .listening:
                PulsingDot()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Listening").font(.headline)
                        if let lastCommand, let lastCommandAt, Date.now.timeIntervalSince(lastCommandAt) < 4 {
                            Text("Heard: \(lastCommand.label)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.basil.opacity(0.18), in: .capsule)
                                .transition(.opacity)
                        }
                    }
                    Text(heard.isEmpty ? "Say next · back · repeat · pause · play · start timer" : "…\(heard)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            case .starting:
                ProgressView()
                Text("Starting the mic…").font(.subheadline)
            case .denied(let permission):
                Image(systemName: "mic.slash").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission == .microphone ? "Microphone access is off" : "Speech recognition is off")
                        .font(.subheadline.weight(.semibold))
                    Text(permission == .microphone
                         ? "Voice control needs the mic. Allow it in Settings, then turn the mic on again."
                         : "Voice control needs speech recognition. Allow it in Settings, then turn the mic on again.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.caption.weight(.semibold))
                }
            case .unavailable:
                Image(systemName: "mic.slash").foregroundStyle(.secondary)
                Text("Speech recognition isn't available right now.").font(.subheadline)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).font(.subheadline).lineLimit(2)
            case .off:
                Image(systemName: "mic").foregroundStyle(.secondary)
                Text("Mic off").font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state.isListening ? Color.red.opacity(0.10) : Theme.card, in: .rect(cornerRadius: 12))
        .animation(.snappy, value: state)
        .animation(.snappy, value: lastCommandAt)
        .accessibilityElement(children: .combine)
    }
}

/// Red "recording" dot that breathes while we listen.
private struct PulsingDot: View {
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 12, height: 12)
            .phaseAnimator([1.0, 0.35]) { view, phase in
                view.opacity(phase)
            } animation: { _ in .easeInOut(duration: 0.7) }
    }
}

/// Timers that belong to other steps (pasta boiling while you sear the shrimp).
struct OtherTimersList: View {
    @Environment(CookSession.self) private var session

    var body: some View {
        let others = session.otherTimers
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Also running").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(others) { timer in
                    StepTimerView(timer: timer)
                }
            }
            .padding()
            .background(Theme.card, in: .rect(cornerRadius: 18))
        }
    }
}
