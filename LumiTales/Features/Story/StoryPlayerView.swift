import SwiftUI
import StoryCharacters

/// Plays one story: the narrator on top, karaoke text of the current segment with the spoken
/// word highlighted, a segment counter, a progress bar and transport controls.
/// Playback pauses automatically when the view disappears or the scene leaves the foreground.
@MainActor
struct StoryPlayerView: View {
    let story: Story

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive

    @State private var rig: CharacterRig
    @State private var player: StoryPlayer
    @State private var segments: [StorySegment] = []
    @State private var hasStarted = false
    /// Set when playback was paused automatically, so it resumes when the view / scene comes back.
    @State private var autoResume = false

    init(story: Story) {
        self.story = story
        let narratorRig = CharacterRig(kind: story.narrator)
        _rig = State(initialValue: narratorRig)
        _player = State(initialValue: StoryPlayer(rig: narratorRig))
    }

    private var isPaused: Bool { !(tabIsActive && scenePhase == .active) }

    private var currentText: String {
        guard !segments.isEmpty else { return "" }
        let index = min(max(player.segmentIndex, 0), segments.count - 1)
        return segments[index].text
    }

    private var clampedProgress: Double {
        min(max(player.progress, 0), 1)
    }

    private var displayedSegmentNumber: Int {
        guard !segments.isEmpty else { return 0 }
        return min(max(player.segmentIndex, 0), segments.count - 1) + 1
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                CharacterView(rig: rig, renderer: .automatic, isPaused: isPaused)
                    .frame(height: min(max(proxy.size.height * 0.38, 200), 400))
                    .overlay(alignment: .bottom) {
                        emotionCaption
                    }

                ScrollView(.vertical) {
                    VStack(spacing: 14) {
                        KaraokeTextView(text: currentText, spokenRange: player.spokenRange)
                        progressPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)

                transportControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .background {
            NightSkyBackground(kind: story.narrator, isPaused: isPaused)
                .ignoresSafeArea()
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            handleDisappear()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if autoResume {
                    autoResume = false
                    player.resume()
                }
            } else if player.state == .playing {
                autoResume = true
                player.pause()
            }
        }
    }

    // MARK: Sub-views

    private var emotionCaption: some View {
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

    private var progressPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.segmentCounter(current: displayedSegmentNumber, total: segments.count))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.playerState(player.state))
                    .foregroundStyle(player.state == .playing ? AppTheme.accent : Color.secondary)
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))

            ProgressView(value: clampedProgress)
                .tint(AppTheme.accent)
                .accessibilityLabel(L10n.storyProgress)

            HStack(spacing: 6) {
                NarratorAvatar(kind: story.narrator, size: 22)
                Text(L10n.narratedBy + " " + story.narrator.displayName(languageCode: L10n.languageCode))
                Spacer()
                Text(story.ageRange)
                Text(story.languageCode.uppercased())
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassPanel()
    }

    private var transportControls: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    autoResume = false
                    player.skipBackward()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(L10n.previousSegment)

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: playbackSymbol)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel(playbackLabel)

                Button {
                    autoResume = false
                    player.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(L10n.stop)
                .disabled(player.state == .idle)

                Button {
                    autoResume = false
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

    // MARK: Playback

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
        if !hasStarted {
            hasStarted = true
            segments = story.script.segments
            player.load(story)
            player.play()
        } else if autoResume {
            autoResume = false
            player.resume()
        }
    }

    private func handleDisappear() {
        if player.state == .playing {
            autoResume = true
            player.pause()
        }
    }
}

/// Current segment text with the word being spoken highlighted from `StoryPlayer.spokenRange`.
struct KaraokeTextView: View {
    let text: String
    let spokenRange: NSRange?

    var body: some View {
        Text(KaraokeTextView.highlight(text, range: spokenRange))
            .font(.system(.title2, design: .rounded, weight: .medium))
            .lineSpacing(6)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassPanel()
            .accessibilityLabel(text)
    }

    /// Builds the attributed text. `range` uses NSRange (UTF-16) semantics relative to `text`.
    static func highlight(_ text: String, range: NSRange?) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = Color.white.opacity(0.92)
        guard let range,
              range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= text.utf16.count,
              let bounds = Range(range, in: result) else {
            return result
        }
        result[bounds].foregroundColor = AppTheme.accent
        result[bounds].backgroundColor = AppTheme.accent.opacity(0.22)
        return result
    }
}
