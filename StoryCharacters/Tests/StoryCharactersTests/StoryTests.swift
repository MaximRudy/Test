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
            XCTAssertGreaterThanOrEqual(script.segments.count, 8)
            XCTAssertLessThanOrEqual(script.segments.count, 12)
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
    }

    func testTemplateGeneratorSanitizesInputAndUsesDefaults() {
        let generator = TemplateStoryGenerator()
        let messy = generator.makeStory(StoryPrompt(heroName: "Dr. [Who]! {x}", setting: "", theme: "", languageCode: "en", narrator: .ember))
        XCTAssertTrue(StoryScript.unknownTags(in: messy.tagged).isEmpty)
        XCTAssertTrue(messy.tagged.contains("Dr Who x"))
        let segments = messy.script.segments
        XCTAssertGreaterThanOrEqual(segments.count, 8)
        XCTAssertLessThanOrEqual(segments.count, 12)
        XCTAssertTrue(messy.tagged.contains("friendship"))
    }

    func testTemplateGeneratorAsync() async throws {
        let generator = TemplateStoryGenerator()
        let prompt = StoryPrompt(heroName: "Nox", setting: "a quiet harbour", theme: "patience", languageCode: "en", narrator: .nox)
        let story = try await generator.generateStory(prompt)
        XCTAssertGreaterThanOrEqual(story.script.segments.count, 8)
        XCTAssertEqual(story, generator.makeStory(prompt))
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
}
