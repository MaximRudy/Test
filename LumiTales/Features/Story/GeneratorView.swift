import SwiftUI
import StoryCharacters

/// A localized preset for the generator pickers. The chosen language's wording is what goes
/// into `StoryPrompt`, so the template generator can place it straight into a sentence.
struct PromptOption: Hashable, Identifiable {
    let ru: String
    let en: String

    var id: String { en }

    func text(_ languageCode: String) -> String {
        languageCode == "ru" ? ru : en
    }
}

/// Picker presets for the generator. Kept outside the view so they are plain nonisolated constants.
enum StoryPresets {
    static let settings: [PromptOption] = [
        PromptOption(ru: "волшебный лес", en: "an enchanted forest"),
        PromptOption(ru: "звёздное небо", en: "the starry sky"),
        PromptOption(ru: "морское дно", en: "the bottom of the sea"),
        PromptOption(ru: "старый замок", en: "an old castle"),
        PromptOption(ru: "снежные горы", en: "the snowy mountains"),
        PromptOption(ru: "цветущий сад", en: "a blooming garden")
    ]

    static let themes: [PromptOption] = [
        PromptOption(ru: "дружба", en: "friendship"),
        PromptOption(ru: "смелость", en: "courage"),
        PromptOption(ru: "доброта", en: "kindness"),
        PromptOption(ru: "любопытство", en: "curiosity"),
        PromptOption(ru: "мечта", en: "a dream"),
        PromptOption(ru: "честность", en: "honesty")
    ]
}

/// "Generate a tale" sheet: fills a `StoryPrompt` and runs `TemplateStoryGenerator` asynchronously.
@MainActor
struct GeneratorView: View {
    var onGenerated: (Story) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var heroName = ""
    @State private var setting: PromptOption = StoryPresets.settings[0]
    @State private var theme: PromptOption = StoryPresets.themes[0]
    @State private var narrator: CharacterKind = .lumi
    @State private var language: String = L10n.languageCode
    @State private var isGenerating = false
    @State private var errorMessage: String?
    /// Live preview of the chosen narrator. Created on first appearance (not in the initializer, which SwiftUI
    /// re-runs whenever the presenting view updates) and replaced when the narrator changes.
    @State private var previewRig: CharacterRig?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            if let previewRig {
                                CharacterView(rig: previewRig, renderer: .swiftUI, isPaused: scenePhase != .active)
                                    .id(ObjectIdentifier(previewRig))
                            }
                        }
                        .frame(width: 180, height: 180)
                        .accessibilityHidden(true)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section(L10n.hero) {
                    TextField(L10n.heroNamePlaceholder, text: $heroName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }

                Section(L10n.storySettings) {
                    Picker(L10n.setting, selection: $setting) {
                        ForEach(StoryPresets.settings) { option in
                            Text(option.text(language)).tag(option)
                        }
                    }
                    Picker(L10n.theme, selection: $theme) {
                        ForEach(StoryPresets.themes) { option in
                            Text(option.text(language)).tag(option)
                        }
                    }
                    Picker(L10n.narrator, selection: $narrator) {
                        ForEach(CharacterKind.presentationOrder) { kind in
                            Text(kind.displayName(languageCode: language)).tag(kind)
                        }
                    }
                    Picker(L10n.language, selection: $language) {
                        Text(verbatim: "Русский").tag("ru")
                        Text(verbatim: "English").tag("en")
                    }
                    .pickerStyle(.segmented)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                Text(L10n.generating)
                            } else {
                                Label(L10n.generate, systemImage: "wand.and.stars")
                            }
                            Spacer()
                        }
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppTheme.onAccent)
                        .tint(AppTheme.onAccent)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isGenerating)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                NightSkyBackground(kind: narrator, isPaused: scenePhase != .active)
                    .ignoresSafeArea()
            }
            .navigationTitle(L10n.generateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        dismiss()
                    }
                    .disabled(isGenerating)
                }
            }
            .onAppear {
                if previewRig == nil {
                    previewRig = CharacterRig(kind: narrator)
                }
            }
            .onChange(of: narrator) { _, kind in
                previewRig = CharacterRig(kind: kind)
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isGenerating)
    }

    private var defaultHeroName: String {
        language == "ru" ? "Алиса" : "Alex"
    }

    private func generate() {
        guard !isGenerating else { return }
        let trimmedName = heroName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = StoryPrompt(heroName: trimmedName.isEmpty ? defaultHeroName : trimmedName,
                                 setting: setting.text(language),
                                 theme: theme.text(language),
                                 languageCode: language,
                                 narrator: narrator)
        isGenerating = true
        errorMessage = nil
        let generator = TemplateStoryGenerator()
        Task {
            do {
                let story = try await generator.generateStory(prompt)
                isGenerating = false
                onGenerated(story)
                dismiss()
            } catch {
                isGenerating = false
                errorMessage = L10n.generationFailed
            }
        }
    }
}
