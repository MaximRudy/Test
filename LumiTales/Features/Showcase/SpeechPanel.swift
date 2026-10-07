import SwiftUI
import StoryCharacters

/// Text-to-speech panel: free text, sample phrases in Russian and English, Say / Stop and a
/// speaking indicator bound to `rig.isSpeaking`. The rig picks the language from the text.
struct SpeechPanel: View {
    let rig: CharacterRig
    @Binding var text: String

    @FocusState private var isFocused: Bool

    static let samplePhrases: [String] = [
        "Привет! Я расскажу тебе сказку.",
        "Жили-были в волшебном лесу маленькие друзья…",
        "Ух ты! Как интересно!",
        "Hello! Shall I tell you a story?",
        "Once upon a time, in a faraway land…",
        "Wow, that was amazing!"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.speech, systemImage: "waveform.and.mic")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                SpeakingIndicator(isSpeaking: rig.isSpeaking)
            }

            TextField(L10n.speechPlaceholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit {
                    say()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
                .accessibilityLabel(L10n.speechPlaceholder)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        say()
                    } label: {
                        Label(L10n.say, systemImage: "play.fill")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(trimmedText.isEmpty)

                    Button(role: .destructive) {
                        rig.stopSpeaking()
                    } label: {
                        Label(L10n.stop, systemImage: "stop.fill")
                            .font(.system(.headline, design: .rounded))
                    }
                    .buttonStyle(.glass)
                    .disabled(!rig.isSpeaking)
                }
            }

            Text(L10n.samplePhrases)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(SpeechPanel.samplePhrases, id: \.self) { phrase in
                        Button {
                            text = phrase
                            isFocused = false
                            rig.speak(phrase)
                        } label: {
                            Text(phrase)
                                .font(.system(.subheadline, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule().fill(Color.white.opacity(0.08))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .contentPanel()
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func say() {
        let phrase = trimmedText
        guard !phrase.isEmpty else { return }
        isFocused = false
        rig.speak(phrase)
    }
}

/// Animated waveform + label that reflects `rig.isSpeaking`.
struct SpeakingIndicator: View {
    let isSpeaking: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: isSpeaking)
            Text(isSpeaking ? L10n.speaking : L10n.silent)
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .foregroundStyle(isSpeaking ? AppTheme.accent : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSpeaking ? L10n.speaking : L10n.silent)
    }
}
