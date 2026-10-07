import XCTest
import Foundation
@testable import StoryCharacters

/// Story module tests: parser, library, generator, Codable and the player's state machine.
/// No GPU, window or audio hardware required — `speak` is never called.
@MainActor
final class StoryTests: XCTestCase {

    // MARK: - Parser

    func testParseTagsPausesAndBreaks() {
        let tagged = "[happy][gesture:wave] Привет, друзья! [curious] Что там?  [pause:0.6] Тишина… Это [br] конец. [pause:1,5]"
        let script = StoryScript.parse(tagged, title: "Тест", languageCode: "ru")

        XCTAssertEqual(script.title, "Тест")
        XCTAssertEqual(script.languageCode, "ru")
        XCTAssertEqual(script.segments.count, 5)
        guard script.segments.count == 5 else { return }
        let s = script.segments

        XCTAssertEqual(s[0].text, "Привет, друзья!")
        XCTAssertEqual(s[0].emotion, .happy)
        XCTAssertEqual(s[0].gesture, .wave)
        XCTAssertEqual(s[0].pauseAfter, StoryScript.defaultPauseAfter, accuracy: 1e-9)

        XCTAssertEqual(s[1].text, "Что там?")
        XCTAssertEqual(s[1].emotion, .curious)
        XCTAssertNil(s[1].gesture)

        XCTAssertEqual(s[2].text, "Тишина…")
        XCTAssertNil(s[2].emotion)
        XCTAssertEqual(s[2].pauseAfter, 0.6, accuracy: 1e-9)

        XCTAssertEqual(s[3].text, "Это")
        XCTAssertNil(s[3].emotion)
        XCTAssertNil(s[3].gesture)

        XCTAssertEqual(s[4].text, "конец.")
        // A trailing pause tag with nothing after it lengthens the final pause (comma decimal accepted).
        XCTAssertEqual(s[4].pauseAfter, 1.5, accuracy: 1e-9)

        XCTAssertEqual(s.map { $0.id }, [0, 1, 2, 3, 4])
    }

    func testPunctuationRunsQuotesAndDecimalsStayWithSentence() {
        let script = StoryScript.parse("Он спросил: «Кто там?» Никто не ответил... Правда?! Да.", title: "", languageCode: "ru")
        XCTAssertEqual(script.segments.map { $0.text },
                       ["Он спросил: «Кто там?»", "Никто не ответил...", "Правда?!", "Да."])

        let decimal = StoryScript.parse("Было 3.5 часа. Пора.", title: "", languageCode: "ru")
        XCTAssertEqual(decimal.segments.map { $0.text }, ["Было 3.5 часа.", "Пора."])
    }

    func testCaseInsensitiveTagsAndUnknownTagsAreDropped() {
        let tagged = "[Happy][gesture:WakeUp][mystery] Hello [thing:x] world. Array [1, 2] is fine."
        let script = StoryScript.parse(tagged, title: "T", languageCode: "en")
        XCTAssertEqual(script.segments.count, 2)
        guard script.segments.count == 2 else { return }
        XCTAssertEqual(script.segments[0].text, "Hello world.")
        XCTAssertEqual(script.segments[0].emotion, .happy)
        XCTAssertEqual(script.segments[0].gesture, .wakeUp)
        // Brackets whose content is not tag-shaped stay literal.
        XCTAssertEqual(script.segments[1].text, "Array [1, 2] is fine.")
        XCTAssertEqual(StoryScript.unknownTags(in: tagged), ["mystery", "thing:x"])
    }

    func testBreakWithoutPunctuationAndMidSentenceTag() {
        let script = StoryScript.parse("One two [br] three four [sad] five.", title: "T", languageCode: "en")
        XCTAssertEqual(script.segments.map { $0.text }, ["One two", "three four five."])
        XCTAssertNil(script.segments.first?.emotion)
        XCTAssertEqual(script.segments.last?.emotion, .sad)
    }

    func testSentencesContinueAfterAbbreviationsDirectSpeechAndLowercase() {
        let abbreviation = StoryScript.parse("[happy][gesture:wave] Mr. Fox waved to the bear. [sad] It rained.",
                                             title: "T", languageCode: "en")
        XCTAssertEqual(abbreviation.segments.map { $0.text }, ["Mr. Fox waved to the bear.", "It rained."])
        XCTAssertEqual(abbreviation.segments.first?.emotion, .happy)
        XCTAssertEqual(abbreviation.segments.first?.gesture, .wave)
        XCTAssertEqual(abbreviation.segments.last?.emotion, .sad)

        let directSpeech = StoryScript.parse("[surprised] «Привет!» — сказал ёжик и улыбнулся. Потом он ушёл.",
                                             title: "T", languageCode: "ru")
        XCTAssertEqual(directSpeech.segments.map { $0.text }, ["«Привет!» — сказал ёжик и улыбнулся.", "Потом он ушёл."])
        XCTAssertEqual(directSpeech.segments.first?.emotion, .surprised)

        let english = StoryScript.parse("\"Hello!\" said the fox. The end.", title: "T", languageCode: "en")
        XCTAssertEqual(english.segments.map { $0.text }, ["\"Hello!\" said the fox.", "The end."])

        let lowercase = StoryScript.parse("Ну... а потом пошёл дождь. Это было в 1999 г. летом.", title: "T", languageCode: "ru")
        XCTAssertEqual(lowercase.segments.map { $0.text }, ["Ну... а потом пошёл дождь.", "Это было в 1999 г. летом."])

        // A dash followed by a capital letter starts a new line of dialogue; "и т. д." before a capital ends a sentence.
        let dialogue = StoryScript.parse("Привет! — Кто там? — Я. Мы ели яблоки и т. д. Потом спали.", title: "T", languageCode: "ru")
        XCTAssertEqual(dialogue.segments.map { $0.text },
                       ["Привет!", "— Кто там?", "— Я.", "Мы ели яблоки и т. д.", "Потом спали."])
    }

    func testRemovedTagsDoNotLeaveSpacesBeforePunctuation() {
        let script = StoryScript.parse("Hello [happy], friend. Yes [sad] ! «Ну [gesture:nod] » — да.", title: "T", languageCode: "ru")
        XCTAssertEqual(script.segments.map { $0.text }, ["Hello, friend.", "Yes!", "«Ну» — да."])
        XCTAssertEqual(script.segments.map { $0.emotion }, [.happy, .sad, nil])
        XCTAssertEqual(script.segments.last?.gesture, .nod)
    }

    func testPlainTextStripsTags() {
        let tagged = "[excited][gesture:celebrate] Ура!\n[sleepy] Пора спать. [pause:2]"
        let script = StoryScript.parse(tagged, title: "T", languageCode: "ru")
        XCTAssertEqual(script.plainText, "Ура! Пора спать.")
        XCTAssertFalse(script.plainText.contains("["))
        XCTAssertFalse(script.plainText.contains("]"))
    }

    func testEmptyInputProducesNoSegments() {
        XCTAssertTrue(StoryScript.parse("", title: "T", languageCode: "en").segments.isEmpty)
        XCTAssertTrue(StoryScript.parse("   [happy] [br]  ", title: "T", languageCode: "en").segments.isEmpty)
        XCTAssertEqual(StoryScript.parse("", title: "T", languageCode: "en").plainText, "")
    }

    // MARK: - Library

    func testBundledStories() {
        let stories = StoryLibrary.bundledStories()
        XCTAssertGreaterThanOrEqual(stories.count, 4)

        var ids = Set<String>()
        var narrators = Set<CharacterKind>()
        for story in stories {
            XCTAssertTrue(ids.insert(story.id).inserted, "duplicate id \(story.id)")
            XCTAssertTrue(narrators.insert(story.narrator).inserted, "narrator \(story.narrator) used twice")
            XCTAssertFalse(story.title.isEmpty)
            XCTAssertFalse(story.summary.isEmpty)
            XCTAssertFalse(story.ageRange.isEmpty)
            let script = story.script
            XCTAssertGreaterThanOrEqual(script.segments.count, 6, story.id)
            XCTAssertLessThanOrEqual(script.segments.count, 14, story.id)
            XCTAssertTrue(StoryScript.unknownTags(in: story.tagged).isEmpty, "unknown tags in \(story.id)")
            XCTAssertTrue(script.segments.allSatisfy { !$0.text.isEmpty })
            XCTAssertTrue(script.segments.contains { $0.gesture != nil }, "\(story.id) has no gestures")
            XCTAssertGreaterThanOrEqual(Set(script.segments.compactMap { $0.emotion }).count, 4, "\(story.id) emotions")
        }
        XCTAssertGreaterThanOrEqual(stories.filter { $0.languageCode == "ru" }.count, 3)
        XCTAssertGreaterThanOrEqual(stories.filter { $0.languageCode == "en" }.count, 1)

        let titles = stories.map { $0.title }
        let sorted = titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(titles, sorted)

        XCTAssertEqual(StoryLibrary.bundledStories(languageCode: "ru-RU").count,
                       stories.filter { $0.languageCode == "ru" }.count)
    }

    // MARK: - Generator

    func testTemplateGeneratorProducesRussianAndEnglishStories() {
        let generator = TemplateStoryGenerator()
        let prompts = [
            StoryPrompt(heroName: "Зайчонок", setting: "Лунная поляна", theme: "дружба", languageCode: "ru", narrator: .lumi),
            StoryPrompt(heroName: "Milo", setting: "the Whispering Hills", theme: "kindness", languageCode: "en-US", narrator: .puff),
        ]
        for prompt in prompts {
            let story = generator.makeStory(prompt)
            let expectedCode = prompt.languageCode.hasPrefix("ru") ? "ru" : "en"
            XCTAssertEqual(story.languageCode, expectedCode)
            XCTAssertEqual(story.narrator, prompt.narrator)
            XCTAssertFalse(story.id.isEmpty)
            XCTAssertFalse(story.title.isEmpty)
            XCTAssertFalse(story.summary.isEmpty)
            XCTAssertTrue(story.tagged.contains(prompt.heroName))
            XCTAssertTrue(story.tagged.contains(prompt.theme))
            XCTAssertTrue(StoryScript.unknownTags(in: story.tagged).isEmpty, "unknown tags: \(StoryScript.unknownTags(in: story.tagged))")

            let script = story.script
            XCTAssertGreaterThanOrEqual(script.segments.count, 6)
            XCTAssertLessThanOrEqual(script.segments.count, 8)
            XCTAssertTrue(script.segments.allSatisfy { !$0.text.isEmpty })
            XCTAssertGreaterThanOrEqual(Set(script.segments.compactMap { $0.emotion }).count, 3)
            XCTAssertGreaterThanOrEqual(script.segments.compactMap { $0.gesture }.count, 2)
            XCTAssertNotNil(script.segments.last?.emotion)
            XCTAssertFalse(script.plainText.contains("{"), "unfilled placeholder in \(script.plainText)")
            XCTAssertFalse(script.plainText.contains("}"))
        }
    }

    func testTemplateGeneratorIsDeterministic() {
        let generator = TemplateStoryGenerator()
        let prompt = StoryPrompt(heroName: "Искорка", setting: "Тихий сад", theme: "смелость", languageCode: "ru", narrator: .spark)
        let first = generator.makeStory(prompt)
        let second = generator.makeStory(prompt)
        XCTAssertEqual(first, second)

        var other = prompt
        other.heroName = "Капелька"
        let different = generator.makeStory(other)
        XCTAssertNotEqual(first.tagged, different.tagged)
        XCTAssertNotEqual(first.id, different.id)

        // Variations are deterministic too, and give the same prompt different tales.
        XCTAssertEqual(first, generator.makeStory(prompt, variation: 0))
        let varied = (1...8).map { generator.makeStory(prompt, variation: UInt64($0)) }
        XCTAssertEqual(varied[0], generator.makeStory(prompt, variation: 1))
        XCTAssertEqual(varied[2], TemplateStoryGenerator(variation: 3).makeStory(prompt))
        XCTAssertEqual(Set(varied.map { $0.id }).count, varied.count)
        XCTAssertFalse(varied.contains { $0.id == first.id })
        XCTAssertGreaterThan(Set(varied.map { $0.tagged }).count, 1)
        for story in varied {
            XCTAssertTrue((6...8).contains(story.script.segments.count), story.tagged)
            XCTAssertTrue(StoryScript.unknownTags(in: story.tagged).isEmpty, story.tagged)
        }
    }

    func testTemplateGeneratorSanitizesInputAndUsesDefaults() {
        let generator = TemplateStoryGenerator()
        let messy = generator.makeStory(StoryPrompt(heroName: "Dr. [Who]! {x}", setting: "", theme: "", languageCode: "en", narrator: .ember))
        XCTAssertTrue(StoryScript.unknownTags(in: messy.tagged).isEmpty)
        XCTAssertTrue(messy.tagged.contains("Dr Who x"))
        let segments = messy.script.segments
        XCTAssertGreaterThanOrEqual(segments.count, 6)
        XCTAssertLessThanOrEqual(segments.count, 8)
        XCTAssertTrue(messy.tagged.contains("friendship"))
    }

    func testTemplateGeneratorAcrossManyPrompts() {
        let generator = TemplateStoryGenerator()
        let heroes = ["Алиса", "Миша", "Alex", "Mia", ""]
        let settings = ["волшебный лес", "снежные горы", "an enchanted forest", "the starry sky", ""]
        let themes = ["доброта", "мечта", "courage", "a dream", ""]
        var ids = Set<String>()
        for (i, kind) in CharacterKind.allCases.enumerated() {
            for language in ["ru", "en"] {
                let prompt = StoryPrompt(heroName: heroes[i % heroes.count],
                                         setting: settings[(i + 1) % settings.count],
                                         theme: themes[(i + 2) % themes.count],
                                         languageCode: language,
                                         narrator: kind)
                let story = generator.makeStory(prompt)
                ids.insert(story.id)
                XCTAssertEqual(story.languageCode, language)
                XCTAssertTrue(StoryScript.unknownTags(in: story.tagged).isEmpty, story.tagged)
                XCTAssertFalse(story.tagged.contains("{"), story.tagged)
                XCTAssertFalse(story.title.contains("{"), story.title)
                let script = story.script
                XCTAssertTrue((6...8).contains(script.segments.count), "\(script.segments.count) segments: \(story.tagged)")
                XCTAssertTrue(script.segments.allSatisfy { $0.emotion != nil }, "every generated sentence carries an emotion")
                XCTAssertGreaterThanOrEqual(script.segments.compactMap { $0.gesture }.count, 4)
                if script.segments.count >= 2 {
                    XCTAssertGreaterThan(script.segments[script.segments.count - 2].pauseAfter, StoryScript.defaultPauseAfter,
                                         "the moral is followed by a longer pause")
                }
            }
        }
        XCTAssertEqual(ids.count, CharacterKind.allCases.count * 2)
    }

    func testTemplateGeneratorAsync() async throws {
        let prompt = StoryPrompt(heroName: "Nox", setting: "a quiet harbour", theme: "patience", languageCode: "en", narrator: .nox)
        let fixed = TemplateStoryGenerator(variation: 7)
        let story = try await fixed.generateStory(prompt)
        XCTAssertTrue((6...8).contains(story.script.segments.count), story.tagged)
        XCTAssertEqual(story, fixed.makeStory(prompt))
        XCTAssertEqual(story, TemplateStoryGenerator().makeStory(prompt, variation: 7))

        // The default generator picks a new variation per call, so "Generate" can tell a new tale.
        let generator = TemplateStoryGenerator()
        var ids = Set<String>()
        for _ in 0..<5 {
            let generated = try await generator.generateStory(prompt)
            XCTAssertTrue((6...8).contains(generated.script.segments.count), generated.tagged)
            ids.insert(generated.id)
        }
        XCTAssertGreaterThan(ids.count, 1)
    }

    // MARK: - Codable

    func testStoryCodableRoundTrip() throws {
        let story = Story(id: "test-1", title: "Тест", languageCode: "ru", narrator: .drop,
                          summary: "Коротко.", ageRange: "3–6",
                          tagged: "[happy] Привет! [pause:0.5] Пока.")
        let data = try JSONEncoder().encode(story)
        let decoded = try JSONDecoder().decode(Story.self, from: data)
        XCTAssertEqual(decoded, story)
        XCTAssertEqual(decoded.script.segments.count, 2)

        let json = """
        {"id":"j","title":"J","languageCode":"en","narrator":"sprout","summary":"s","ageRange":"3–6","tagged":"[love] Hi."}
        """
        let fromJSON = try JSONDecoder().decode(Story.self, from: Data(json.utf8))
        XCTAssertEqual(fromJSON.narrator, .sprout)
        XCTAssertEqual(fromJSON.script.segments.first?.emotion, .love)
        XCTAssertEqual(fromJSON.script.segments.first?.text, "Hi.")
    }

    // MARK: - Player (no speech)

    func testStoryPlayerStateMachineWithoutSpeaking() {
        let rig = CharacterRig(kind: .lumi)
        let player = StoryPlayer(rig: rig)
        XCTAssertEqual(player.state, .idle)
        XCTAssertNil(player.story)
        XCTAssertEqual(player.progress, 0, accuracy: 1e-9)
        XCTAssertNil(player.currentSegment)

        // Transport calls are harmless with nothing loaded.
        player.pause()
        player.resume()
        player.skipForward()
        player.skipBackward()
        XCTAssertEqual(player.state, .idle)

        let story = Story(id: "p", title: "P", languageCode: "en", narrator: .lumi, summary: "", ageRange: "3–6",
                          tagged: "[happy] One. [sad] Two. [excited][gesture:bounce] Three. Four.")
        player.load(story)
        XCTAssertEqual(player.story, story)
        XCTAssertEqual(player.segments.count, 4)
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.segmentIndex, 0)
        XCTAssertEqual(player.currentSegment?.text, "One.")
        XCTAssertEqual(player.progress, 0, accuracy: 1e-9)

        player.skipForward()
        XCTAssertEqual(player.segmentIndex, 1)
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.progress, 0.25, accuracy: 1e-9)
        player.skipForward()
        player.skipForward()
        XCTAssertEqual(player.segmentIndex, 3)
        player.skipForward()   // already on the last segment while idle: stays idle
        XCTAssertEqual(player.segmentIndex, 3)
        XCTAssertEqual(player.state, .idle)

        player.skipBackward()
        XCTAssertEqual(player.segmentIndex, 2)
        XCTAssertEqual(player.currentSegment?.gesture, .bounce)

        rig.set(emotion: .happy)
        player.stop()
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.segmentIndex, 0)
        XCTAssertNil(player.spokenRange)
        XCTAssertEqual(rig.emotion, .neutral)
        XCTAssertNotNil(player.story, "stop keeps the story loaded")

        player.detach()
        XCTAssertEqual(player.state, .idle)
    }

    func testEffectiveEmotionCarriesForward() {
        let player = StoryPlayer(rig: CharacterRig(kind: .sprout))
        XCTAssertEqual(player.effectiveEmotion(at: 0), .neutral)
        player.load(Story(id: "e", title: "E", languageCode: "en", narrator: .sprout, summary: "", ageRange: "3–6",
                          tagged: "Calm. [happy] Yay. More. [sad] Oh. Hm."))
        XCTAssertEqual((0..<5).map { player.effectiveEmotion(at: $0) }, [.neutral, .happy, .happy, .sad, .sad])
        XCTAssertEqual(player.effectiveEmotion(at: 99), .sad)
    }

    /// Drives the player with synthetic speech events through `rig.onSpeechEvent`; `speakOverride`
    /// replaces the real TTS so no audio is involved.
    func testStoryPlayerSequencingWithInjectedSpeech() async throws {
        let rig = CharacterRig(kind: .nox)
        var observed: [SpeechEvent] = []
        rig.onSpeechEvent = { event in observed.append(event) }

        let player = StoryPlayer(rig: rig)
        var spoken: [String] = []
        var languages: [String?] = []
        player.speakOverride = { text, language in
            spoken.append(text)
            languages.append(language)
        }
        let story = Story(id: "seq", title: "Seq", languageCode: "en", narrator: .nox, summary: "", ageRange: "3–6",
                          tagged: "[pause:0][happy][gesture:wave] Hello there. [pause:0][sad] Rain falls. [pause:0] Still raining.")
        player.load(story)
        player.play()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(spoken, ["Hello there."])
        XCTAssertEqual(languages, ["en"])
        XCTAssertEqual(rig.emotion, .happy)
        XCTAssertEqual(rig.activeGesture, .wave)

        // Word highlighting uses UTF-16 ranges inside the segment text; out-of-range words are ignored.
        rig.onSpeechEvent?(.started(text: "Hello there."))
        rig.onSpeechEvent?(.word(location: 6, length: 5, text: "there"))
        XCTAssertEqual(player.spokenRange, NSRange(location: 6, length: 5))
        rig.onSpeechEvent?(.word(location: 40, length: 3, text: "bad"))
        XCTAssertEqual(player.spokenRange, NSRange(location: 6, length: 5))
        XCTAssertEqual(observed.count, 3, "the previously installed handler is chained")

        rig.onSpeechEvent?(.finished)
        XCTAssertNil(player.spokenRange)
        XCTAssertTrue(player.isCurrentSegmentSpoken)
        XCTAssertEqual(player.progress, 1.0 / 3.0, accuracy: 1e-9)
        try await waitUntil { spoken.count == 2 }
        XCTAssertEqual(player.segmentIndex, 1)
        XCTAssertEqual(spoken.last, "Rain falls.")
        XCTAssertEqual(rig.emotion, .sad)
        XCTAssertEqual(player.progress, 1.0 / 3.0, accuracy: 1e-9)

        // An interruption from outside pauses on the current sentence; resume re-speaks it.
        rig.onSpeechEvent?(.cancelled)
        XCTAssertEqual(player.state, .paused)
        player.resume()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(spoken.count, 3)
        XCTAssertEqual(spoken.last, "Rain falls.")

        // Pausing mid-sentence keeps the position.
        player.pause()
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(player.segmentIndex, 1)
        rig.onSpeechEvent?(.finished)   // ignored while paused
        XCTAssertEqual(player.segmentIndex, 1)
        player.resume()
        XCTAssertEqual(spoken.count, 4)

        rig.onSpeechEvent?(.finished)
        try await waitUntil { spoken.count == 5 }
        XCTAssertEqual(player.segmentIndex, 2)
        XCTAssertEqual(spoken.last, "Still raining.")
        XCTAssertEqual(rig.emotion, .sad, "untagged sentences keep the previous emotion")

        rig.onSpeechEvent?(.finished)
        try await waitUntil { player.state == .finished }
        XCTAssertEqual(player.progress, 1, accuracy: 1e-9)

        // Playing a finished story starts from the top.
        player.play()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(player.segmentIndex, 0)
        XCTAssertEqual(spoken.last, "Hello there.")

        player.stop()
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(rig.emotion, .neutral)
        rig.onSpeechEvent?(.word(location: 0, length: 5, text: "Hello"))
        XCTAssertNil(player.spokenRange, "events are ignored once stopped")

        player.detach()
        rig.onSpeechEvent?(.finished)
        XCTAssertEqual(observed.last, SpeechEvent.finished, "detach restores the previous handler")
    }

    func testPauseDuringSilenceResumesWithNextSentence() async throws {
        let rig = CharacterRig(kind: .puff)
        let player = StoryPlayer(rig: rig)
        var spoken: [String] = []
        player.speakOverride = { text, _ in spoken.append(text) }
        player.load(Story(id: "s", title: "S", languageCode: "ru", narrator: .puff, summary: "", ageRange: "3–6",
                          tagged: "[pause:5] Раз. Два."))
        player.play()
        XCTAssertEqual(spoken, ["Раз."])
        rig.onSpeechEvent?(.finished)
        XCTAssertTrue(player.isCurrentSegmentSpoken)
        XCTAssertEqual(player.progress, 0.5, accuracy: 1e-9)

        player.pause()
        XCTAssertEqual(player.state, .paused)
        player.resume()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(player.segmentIndex, 1)
        XCTAssertEqual(spoken, ["Раз.", "Два."])

        player.skipForward()   // on the last segment while playing: finishes
        XCTAssertEqual(player.state, .finished)
        player.skipBackward()  // rewinding a finished story parks it on the last segment
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.segmentIndex, 1)
        player.detach()
    }

    func testGestureStaging() {
        XCTAssertEqual(StoryPlayer.staging(of: .yawn), .leadIn)
        XCTAssertEqual(StoryPlayer.staging(of: .wakeUp), .leadIn)
        XCTAssertEqual(StoryPlayer.staging(of: .sleep), .trailing)
        XCTAssertEqual(StoryPlayer.staging(of: .wave), .withSpeech)
        XCTAssertEqual(StoryPlayer.staging(of: .nod), .withSpeech)
        for gesture in Gesture.allCases {
            XCTAssertGreaterThan(StoryPlayer.gestureDuration(gesture, emotion: .neutral), 0, gesture.rawValue)
        }
        XCTAssertGreaterThan(StoryPlayer.gestureDuration(.yawn, emotion: .sleepy),
                             StoryPlayer.gestureDuration(.yawn, emotion: .excited),
                             "calm emotions stretch gestures")
    }

    /// A yawn plays before its sentence (speech starts near its end) and `sleep` after it; the story waits for it.
    func testLeadInAndTrailingGesturesAreStagedAroundSpeech() async throws {
        let rig = CharacterRig(kind: .lumie)
        let player = StoryPlayer(rig: rig)
        player.gestureTimeScale = 0.02
        var spoken: [String] = []
        player.speakOverride = { text, _ in spoken.append(text) }
        player.load(Story(id: "g", title: "G", languageCode: "en", narrator: .lumie, summary: "", ageRange: "3–6",
                          tagged: "[pause:0][sleepy][gesture:yawn] So sleepy now. [pause:0][gesture:sleep] Good night."))
        player.play()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(rig.activeGesture, .yawn)
        XCTAssertTrue(spoken.isEmpty, "the narrator waits for the yawn before talking")
        try await waitUntil { spoken.count == 1 }
        XCTAssertEqual(spoken, ["So sleepy now."])

        rig.onSpeechEvent?(.finished)
        try await waitUntil { spoken.count == 2 }
        XCTAssertEqual(player.segmentIndex, 1)
        XCTAssertEqual(spoken.last, "Good night.")
        XCTAssertNotEqual(rig.activeGesture, .sleep, "sleep waits until the sentence has been said")

        rig.onSpeechEvent?(.finished)
        XCTAssertEqual(rig.activeGesture, .sleep)
        XCTAssertEqual(player.state, .playing, "the story waits for the sleep gesture")
        XCTAssertEqual(player.progress, 1, accuracy: 1e-9)
        try await waitUntil { player.state == .finished }
        player.detach()
    }

    func testPauseDuringLeadInGestureSpeaksOnResumeWithoutReplayingIt() {
        let rig = CharacterRig(kind: .nox)
        let player = StoryPlayer(rig: rig)
        var spoken: [String] = []
        player.speakOverride = { text, _ in spoken.append(text) }
        player.load(Story(id: "w", title: "W", languageCode: "en", narrator: .nox, summary: "", ageRange: "3–6",
                          tagged: "[gesture:wakeUp] Good morning. Second."))
        player.play()
        XCTAssertEqual(rig.activeGesture, .wakeUp)
        XCTAssertTrue(spoken.isEmpty)

        player.pause()
        XCTAssertEqual(player.state, .paused)
        rig.play(.nod)   // marker: a replayed wakeUp would replace it
        player.resume()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(spoken, ["Good morning."], "resuming speaks at once")
        XCTAssertEqual(rig.activeGesture, .nod, "the lead-in gesture is not replayed")

        player.skipForward()
        XCTAssertEqual(spoken, ["Good morning.", "Second."])
        player.stop()
        player.detach()
    }

    /// The speech engine pausing by itself (audio-session interruption) is mirrored instead of being
    /// skipped by the watchdog.
    func testSpeechEnginePauseIsMirrored() async throws {
        let rig = CharacterRig(kind: .drop)
        let player = StoryPlayer(rig: rig)
        var spoken: [String] = []
        player.speakOverride = { text, _ in spoken.append(text) }
        player.load(Story(id: "ep", title: "EP", languageCode: "en", narrator: .drop, summary: "", ageRange: "3–6",
                          tagged: "[pause:0] One. [pause:0] Two."))
        player.play()
        XCTAssertEqual(spoken, ["One."])

        rig.onSpeechEvent?(.paused)
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(player.segmentIndex, 0)
        rig.onSpeechEvent?(.resumed)
        XCTAssertEqual(player.state, .playing)
        rig.onSpeechEvent?(.finished)
        try await waitUntil { spoken.count == 2 }
        XCTAssertEqual(player.segmentIndex, 1)

        // An engine pause followed by the user's resume re-speaks the sentence.
        rig.onSpeechEvent?(.paused)
        XCTAssertEqual(player.state, .paused)
        player.resume()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(spoken, ["One.", "Two.", "Two."])

        // `.resumed` without a preceding engine pause is ignored.
        player.pause()
        rig.onSpeechEvent?(.resumed)
        XCTAssertEqual(player.state, .paused)
        player.stop()
        player.detach()
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout) s")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
