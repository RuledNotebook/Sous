import SwiftUI

/// The empty state: paste a YouTube link, optionally its transcript, make the slideshow.
struct InputFormView: View {
    @Environment(CookSession.self) private var session
    @State private var showTranscript = false
    @FocusState private var focused: Field?

    private enum Field { case link, transcript }

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cook along to a YouTube video")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Paste the link. You get step-by-step slides with real kitchen times.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("youtube.com/watch?v=…", text: $session.linkText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focused, equals: .link)
                            .onSubmit { if session.canMakeSlideshow { Task { await session.makeSlideshow() } } }
                            .accessibilityLabel("YouTube link")
                        PasteButton(payloadType: String.self) { strings in
                            session.linkText = strings.first ?? ""
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.roundedRectangle)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Paste link")
                    }
                    if !session.linkText.isEmpty, session.youtubeURL == nil {
                        Text("That doesn't look like a YouTube link.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup(isExpanded: $showTranscript) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On YouTube, open the video's description, tap Show transcript, select it all and copy.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $session.transcriptText)
                            .font(.callout)
                            .frame(minHeight: 120, maxHeight: 220)
                            .padding(6)
                            .background(Theme.canvas, in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                            .focused($focused, equals: .transcript)
                            .accessibilityLabel("Transcript")
                        HStack {
                            PasteButton(payloadType: String.self) { strings in
                                session.transcriptText = strings.first ?? ""
                            }
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Paste transcript")
                            Spacer()
                            if !session.transcriptText.isEmpty {
                                Text("\(wordCount) words").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Transcript (optional)", systemImage: "text.quote")
                    .font(.subheadline)
                }

                switch session.phase {
                case .working:
                    ProgressView("Reading the recipe…")
                        .frame(maxWidth: .infinity)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                        .accessibilityLabel("Error: \(message)")
                default:
                    EmptyView()
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons }
                    VStack(spacing: 10) { buttons }
                }

                Text("Ingredient art: Microsoft Fluent Emoji, MIT license.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var buttons: some View {
        Button {
            focused = nil
            Task { await session.makeSlideshow() }
        } label: {
            Label("Make slideshow", systemImage: "sparkles")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.actionFill)
        .disabled(!session.canMakeSlideshow)

        Button("Demo") { Task { await session.loadDemo() } }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(session.phase == .working)
            .accessibilityLabel("Show the demo recipe")
    }

    private var wordCount: Int {
        session.transcriptText.split(whereSeparator: \.isWhitespace).count
    }
}
