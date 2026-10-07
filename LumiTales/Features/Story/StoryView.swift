import SwiftUI
import StoryCharacters

/// Gives every listed story a unique, Hashable identity for navigation. `Story` itself is not
/// Hashable, and generated stories may repeat ids, so navigation keys off this wrapper instead.
struct StoryEntry: Identifiable, Hashable {
    let id: UUID
    let story: Story

    init(story: Story) {
        id = UUID()
        self.story = story
    }

    static func == (lhs: StoryEntry, rhs: StoryEntry) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Stories tab: bundled library + stories generated in this session, and the "Generate" sheet.
struct StoryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive

    @State private var bundled: [StoryEntry] = []
    @State private var generated: [StoryEntry] = []
    @State private var path: [StoryEntry] = []
    @State private var showsGenerator = false
    @State private var pendingEntry: StoryEntry?
    @State private var hasLoadedLibrary = false

    private var isPaused: Bool { !(tabIsActive && scenePhase == .active) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    generateCard

                    if !generated.isEmpty {
                        sectionHeader(L10n.yourStories)
                        ForEach(generated) { entry in
                            storyLink(entry)
                        }
                    }

                    sectionHeader(L10n.library)
                    if bundled.isEmpty && hasLoadedLibrary {
                        ContentUnavailableView {
                            Label(L10n.noStories, systemImage: "book.closed")
                        } description: {
                            Text(L10n.noStoriesHint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        ForEach(bundled) { entry in
                            storyLink(entry)
                        }
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .background {
                NightSkyBackground(kind: .lumi, isPaused: isPaused)
                    .ignoresSafeArea()
            }
            .navigationTitle(L10n.storiesTab)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsGenerator = true
                    } label: {
                        Label(L10n.generate, systemImage: "wand.and.stars")
                    }
                    .accessibilityLabel(L10n.generate)
                }
            }
            .navigationDestination(for: StoryEntry.self) { entry in
                StoryPlayerView(story: entry.story)
            }
            .sheet(isPresented: $showsGenerator, onDismiss: { openPendingStory() }) {
                GeneratorView { story in
                    let entry = StoryEntry(story: story)
                    generated.insert(entry, at: 0)
                    pendingEntry = entry
                }
            }
            .onAppear {
                loadLibraryIfNeeded()
            }
        }
    }

    /// Prominent entry point to the generator at the top of the list.
    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.generateHint)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                showsGenerator = true
            } label: {
                Label(L10n.generate, systemImage: "wand.and.stars")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(14)
        .contentPanel(cornerRadius: 22)
    }

    private func storyLink(_ entry: StoryEntry) -> some View {
        NavigationLink(value: entry) {
            StoryRow(story: entry.story)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func loadLibraryIfNeeded() {
        guard !hasLoadedLibrary else { return }
        hasLoadedLibrary = true
        bundled = StoryLibrary.bundledStories().map { StoryEntry(story: $0) }
    }

    /// The generator sheet hands over its story before dismissing; the push happens once the sheet is gone.
    private func openPendingStory() {
        guard let entry = pendingEntry else { return }
        pendingEntry = nil
        path.append(entry)
    }
}

/// One story card in the list.
struct StoryRow: View {
    let story: Story

    var body: some View {
        HStack(spacing: 14) {
            NarratorAvatar(kind: story.narrator, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(story.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.white)
                Text(story.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(story.narrator.displayName(languageCode: L10n.languageCode), systemImage: "person.wave.2")
                    Text(L10n.ageRange(story.ageRange))
                    Text(story.languageCode.uppercased())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background {
                            Capsule().fill(Color.white.opacity(0.1))
                        }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentPanel(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Static avatar: the character's body gradient with its initial. Used where a live rig would be wasteful.
struct NarratorAvatar: View {
    let kind: CharacterKind
    var size: CGFloat = 56

    var body: some View {
        let palette = CharacterCatalog.design(for: kind).palette
        ZStack {
            Circle()
                .fill(AppTheme.bodyGradient(for: kind))
            Circle()
                .strokeBorder(AppTheme.color(palette.glow).opacity(0.7), lineWidth: max(1, size * 0.04))
            Text(String(kind.displayName(languageCode: L10n.languageCode).prefix(1)))
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.color(palette.outline))
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.color(palette.glow).opacity(0.5), radius: size * 0.15)
        .accessibilityHidden(true)
    }
}
