import SwiftUI
import StoryCharacters

/// Plays one story: the narrator on top, karaoke text of the current segment with the spoken
/// word highlighted, a segment counter, a progress bar and transport controls.
/// Playback pauses automatically when the view disappears or the scene leaves the foreground.
///
/// The narrator rig and the `StoryPlayer` are created on first appearance rather than in the initializer:
/// SwiftUI re-runs this initializer whenever the navigation destination is re-evaluated, and objects built
/// there would be thrown away by `@State` each time.
@MainActor
struct StoryPlayerView: View {
    let story: Story

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive

    @State private var rig: CharacterRig?
    @State private var player: StoryPlayer?

    private var isPaused: Bool { !(tabIsActive && scenePhase == .active) }

    var body: some View {
        ZStack {
            if let rig, let player {
                StoryPlayerScreen(story: story, rig: rig, player: player)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            NightSkyBackground(kind: story.narrator, isPaused: isPaused)
                .ignoresSafeArea()
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if rig == nil || player == nil {
                let narratorRig = CharacterRig(kind: story.narrator)
                rig = narratorRig
                player = StoryPlayer(rig: narratorRig)
            }
        }
    }
}

/// The player screen proper. Its own body reads nothing observable from the rig or the player: the parts
/// that change often live in small sub-views (`KaraokeTextView` for the spoken word, `StoryProgressPanel`,
/// `StoryTransportBar`, `NarratorStage`), so a word callback re-evaluates only the karaoke text.
///
/// Layout: narrator above the text; in compact height (iPhone landscape) narrator and text side by side.
/// On wide screens the text column is capped at 640 pt.
@MainActor
struct StoryPlayerScreen: View {
    let story: Story
    let rig: CharacterRig
    let player: StoryPlayer

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var segments: [StorySegment] = []
    @State private var hasStarted = false
    /// True between `onAppear` and `onDisappear`.
    @State private var isVisible = false
    /// Set when playback was paused automatically, so it resumes once the view is visible and the scene active again.
    @State private var autoResume = false

    private var isPaused: Bool { !(tabIsActive && scenePhase == .active) }

    /// Narration may run only while the player is on screen, in the visible tab, in an active scene.
    private var canNarrate: Bool { isVisible && tabIsActive && scenePhase == .active }

    var body: some View {
        GeometryReader { proxy in
            let isCompactHeight = verticalSizeClass == .compact
            let layout = isCompactHeight
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                NarratorStage(rig: rig, isPaused: isPaused)
                    .frame(width: isCompactHeight ? proxy.size.width * 0.42 : nil,
                           height: isCompactHeight ? nil : min(max(proxy.size.height * 0.38, 200), 400))

                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        VStack(spacing: 14) {
                            KaraokeTextView(player: player, segments: segments)
                            StoryProgressPanel(player: player, story: story, segmentCount: segments.count)
                        }
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)

                    StoryTransportBar(player: player,
                                      onUserAction: {
                                          autoResume = false
                                      },
                                      onTogglePlayback: {
                                          togglePlayback()
                                      })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            handleDisappear()
        }
        .onChange(of: scenePhase) { _, _ in
            syncAutoPause()
        }
        .onChange(of: tabIsActive) { _, _ in
            syncAutoPause()
        }
    }

    // MARK: Playback

    private func togglePlayback() {
        autoResume = false
        switch player.state {
        case .idle:
            player.play()
        case .playing:
            player.pause()
        case .paused:
            player.resume()
        case .finished:
            player.stop()
            player.play()
        }
    }

    private func handleAppear() {
        isVisible = true
        if !hasStarted {
            hasStarted = true
            segments = story.script.segments
            player.load(story)
            if canNarrate {
                player.play()
            }
        } else {
            syncAutoPause()
        }
    }

    private func handleDisappear() {
        isVisible = false
        syncAutoPause()
    }

    /// Pauses automatically when narration is not allowed (view gone, tab hidden, scene inactive) and
    /// resumes only what was paused automatically once it is allowed again.
    private func syncAutoPause() {
        if canNarrate {
            if autoResume {
                autoResume = false
                if player.state == .paused {
                    player.resume()
                }
            }
        } else if player.state == .playing {
            autoResume = true
            player.pause()
        }
    }
}

// MARK: - Narrator

/// The narrating character with its "<name>, <emotion>" accessibility label and a floating emotion caption.
/// Reads only `rig.emotion` (at most once per sentence); the caption observes `isSpeaking` on its own.
struct NarratorStage: View {
    let rig: CharacterRig
    let isPaused: Bool

    private var accessibilityText: String {
        rig.design.kind.displayName(languageCode: L10n.languageCode)
            + ", "
            + rig.emotion.displayName(languageCode: L10n.languageCode)
    }

    var body: some View {
        CharacterView(rig: rig, renderer: .automatic, isPaused: isPaused)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isImage)
            .overlay(alignment: .bottom) {
                NarratorEmotionCaption(rig: rig)
            }
    }
}

/// Small glass caption under the narrator: current emotion and a waveform while speaking.
struct NarratorEmotionCaption: View {
    let rig: CharacterRig

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: rig.emotion.symbolName)
            Text(rig.emotion.displayName(languageCode: L10n.languageCode))
            if rig.isSpeaking {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect()
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// Segment counter, player state, progress bar and story facts. Changes once per segment.
struct StoryProgressPanel: View {
    let player: StoryPlayer
    let story: Story
    let segmentCount: Int

    private var displayedSegmentNumber: Int {
        guard segmentCount > 0 else { return 0 }
        return min(max(player.segmentIndex, 0), segmentCount - 1) + 1
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.segmentCounter(current: displayedSegmentNumber, total: segmentCount))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.playerState(player.state))
                    .foregroundStyle(player.state == .playing ? AppTheme.accent : Color.secondary)
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))

            ProgressView(value: min(max(player.progress, 0), 1))
                .tint(AppTheme.accent)
                .accessibilityLabel(L10n.storyProgress)

            HStack(spacing: 6) {
                NarratorAvatar(kind: story.narrator, size: 22)
                Text(L10n.narratedBy + " " + story.narrator.displayName(languageCode: L10n.languageCode))
                Spacer()
                Text(L10n.ageRange(story.ageRange))
                Text(story.languageCode.uppercased())
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .contentPanel()
    }
}

// MARK: - Transport

/// Floating Liquid Glass transport bar: previous, play / pause / replay, stop, next.
/// `onUserAction` runs before every manual transport action so the owner can cancel its auto-resume.
struct StoryTransportBar: View {
    let player: StoryPlayer
    let onUserAction: () -> Void
    let onTogglePlayback: () -> Void

    private var playbackSymbol: String {
        switch player.state {
        case .playing: return "pause.fill"
        case .finished: return "arrow.counterclockwise"
        case .idle, .paused: return "play.fill"
        }
    }

    private var playbackLabel: String {
        switch player.state {
        case .playing: return L10n.pause
        case .paused: return L10n.resume
        case .finished: return L10n.replay
        case .idle: return L10n.play
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    onUserAction()
                    player.skipBackward()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(L10n.previousSegment)

                Button {
                    onTogglePlayback()
                } label: {
                    Image(systemName: playbackSymbol)
                        .font(.title2)
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel(playbackLabel)

                Button {
                    onUserAction()
                    player.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(L10n.stop)
                .disabled(player.state == .idle)

                Button {
                    onUserAction()
                    player.skipForward()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(L10n.nextSegment)
            }
            .font(.title3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Karaoke text

/// Current segment text with the word being spoken highlighted from `StoryPlayer.spokenRange`.
/// Text already heard is bright, the current word is golden, the rest of the sentence is dimmed.
///
/// `spokenRange` is nil between words, in the pause after a sentence and while paused. The view remembers
/// how far the current segment has been spoken, so in those gaps the split stays where it was instead of
/// flashing back to a uniform colour; once the last word has been spoken the whole sentence reads as heard.
/// The text is uniform only while the player is idle (not started or stopped).
struct KaraokeTextView: View {
    let player: StoryPlayer
    let segments: [StorySegment]

    /// Segment that `heardEnd` belongs to (-1 = none).
    @State private var heardSegment = -1
    /// UTF-16 offset up to which `heardSegment` has been spoken.
    @State private var heardEnd = 0

    private var segmentIndex: Int {
        guard !segments.isEmpty else { return 0 }
        return min(max(player.segmentIndex, 0), segments.count - 1)
    }

    var body: some View {
        let index = segmentIndex
        let text = segments.isEmpty ? "" : segments[index].text
        let state = player.state
        let range = player.spokenRange
        let isNarrating = state != .idle
        let heard = (isNarrating && index == heardSegment) ? heardEnd : 0

        Text(KaraokeTextView.highlight(text, range: range, heardUpTo: heard, isNarrating: isNarrating))
            .font(.system(.title2, design: .rounded, weight: .medium))
            .lineSpacing(6)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .contentPanel()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.storyText)
            .accessibilityValue(text)
            .onChange(of: range) { _, newRange in
                record(newRange)
            }
            .onChange(of: index) { _, _ in
                resetHeard()
            }
            .onChange(of: state) { _, newState in
                if newState == .idle {
                    resetHeard()
                }
            }
    }

    /// Remembers the end of the latest spoken word of the current segment. Word ranges grow within one
    /// utterance; a resumed segment is re-spoken from its start, and its first word moves the mark back.
    private func record(_ range: NSRange?) {
        guard let range, range.location != NSNotFound, range.length > 0 else { return }
        heardSegment = segmentIndex
        heardEnd = NSMaxRange(range)
    }

    private func resetHeard() {
        heardSegment = -1
        heardEnd = 0
    }

    private static let plainColor = Color.white.opacity(0.92)
    private static let spokenColor = Color.white
    private static let upcomingColor = Color.white.opacity(0.62)

    /// Builds the attributed text. `range` and `heard` use NSRange (UTF-16) semantics relative to `text`.
    static func highlight(_ text: String, range: NSRange?, heardUpTo heard: Int, isNarrating: Bool) -> AttributedString {
        let length = text.utf16.count

        // A word is being spoken: heard text, golden word, dimmed rest.
        if let range,
           range.location != NSNotFound,
           range.length > 0,
           NSMaxRange(range) <= length,
           let bounds = Range<String.Index>(range, in: text) {
            var result = AttributedString(String(text[text.startIndex..<bounds.lowerBound]))
            result.foregroundColor = spokenColor

            var word = AttributedString(String(text[bounds]))
            word.foregroundColor = AppTheme.accent
            word.backgroundColor = AppTheme.accent.opacity(0.22)

            var rest = AttributedString(String(text[bounds.upperBound..<text.endIndex]))
            rest.foregroundColor = upcomingColor

            result.append(word)
            result.append(rest)
            return result
        }

        // Idle: one uniform, easy-to-read colour.
        guard isNarrating else {
            var plain = AttributedString(text)
            plain.foregroundColor = plainColor
            return plain
        }

        // Between words: keep the heard / upcoming split at the last spoken position.
        let heardLength = min(max(heard, 0), length)
        guard heardLength > 0,
              let heardBounds = Range<String.Index>(NSRange(location: 0, length: heardLength), in: text) else {
            var upcoming = AttributedString(text)
            upcoming.foregroundColor = upcomingColor
            return upcoming
        }

        let restText = text[heardBounds.upperBound..<text.endIndex]
        if !restText.contains(where: { $0.isLetter || $0.isNumber }) {
            // Only punctuation or spaces remain: the sentence has been spoken completely.
            var spoken = AttributedString(text)
            spoken.foregroundColor = spokenColor
            return spoken
        }

        var result = AttributedString(String(text[text.startIndex..<heardBounds.upperBound]))
        result.foregroundColor = spokenColor
        var rest = AttributedString(String(restText))
        rest.foregroundColor = upcomingColor
        result.append(rest)
        return result
    }
}
