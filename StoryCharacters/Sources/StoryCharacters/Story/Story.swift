import Foundation

// MARK: - Story

/// A story as stored on disk / produced by a generator: metadata plus the tagged source text.
/// JSON keys are exactly the property names (`id`, `title`, `languageCode`, `narrator`, `summary`, `ageRange`, `tagged`).
public struct Story: Sendable, Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    /// "ru" / "en" (or any BCP-47 code the speech driver accepts).
    public var languageCode: String
    /// The character that tells the story.
    public var narrator: CharacterKind
    public var summary: String
    /// Free-form, e.g. "3–6".
    public var ageRange: String
    /// Source text with `[emotion]`, `[gesture:x]`, `[pause:n]` and `[br]` tags (see `StoryScript`).
    public var tagged: String

    public init(id: String, title: String, languageCode: String, narrator: CharacterKind,
                summary: String, ageRange: String, tagged: String) {
        self.id = id
        self.title = title
        self.languageCode = languageCode
        self.narrator = narrator
        self.summary = summary
        self.ageRange = ageRange
        self.tagged = tagged
    }

    /// The parsed, playable form. Parsing is cheap but not free — cache it when rendering lists.
    public var script: StoryScript {
        StoryScript.parse(tagged, title: title, languageCode: languageCode)
    }

    /// True for Russian-language stories ("ru", "ru-RU", …).
    public var isRussian: Bool {
        languageCode.lowercased().hasPrefix("ru")
    }
}

// MARK: - StoryLibrary

/// Access to the stories bundled with the package (`Resources/Stories/*.json`).
public enum StoryLibrary {
    /// Last-resort list used when the bundle cannot enumerate its JSON resources.
    static let fallbackFileNames: [String] = [
        "ru-lumi-star-library",
        "ru-nox-moon-lullaby",
        "ru-sprout-patient-seed",
        "en-lumie-firefly-jar",
        "en-puff-soft-pillow",
    ]

    /// Decodes every bundled story JSON. Undecodable files are skipped, duplicates (same `id`) are dropped,
    /// the result is sorted by title. Never crashes on a bad file.
    public static func bundledStories() -> [Story] {
        let bundle = Bundle.module
        var urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Stories") ?? []
        if urls.isEmpty {
            urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        }
        if urls.isEmpty {
            urls = fallbackFileNames.compactMap { bundle.url(forResource: $0, withExtension: "json") }
        }
        return decodeStories(at: urls)
    }

    /// Bundled stories in a given language ("ru" matches "ru-RU" as well).
    public static func bundledStories(languageCode: String) -> [Story] {
        let wanted = baseLanguage(languageCode)
        return bundledStories().filter { baseLanguage($0.languageCode) == wanted }
    }

    static func decodeStories(at urls: [URL]) -> [Story] {
        let decoder = JSONDecoder()
        var seenIDs = Set<String>()
        var stories: [Story] = []
        stories.reserveCapacity(urls.count)
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let story = try? decoder.decode(Story.self, from: data) else { continue }
            guard !story.id.isEmpty, !story.tagged.isEmpty, seenIDs.insert(story.id).inserted else { continue }
            stories.append(story)
        }
        return stories.sorted { lhs, rhs in
            let order = lhs.title.localizedStandardCompare(rhs.title)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    /// "ru-RU" → "ru", "en_US" → "en".
    static func baseLanguage(_ code: String) -> String {
        let lowered = code.lowercased()
        if let separator = lowered.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            return String(lowered[lowered.startIndex..<separator])
        }
        return lowered
    }
}
