import XCTest
import AVFoundation
import QuartzCore
@testable import StoryCharacters

@MainActor
final class LipSyncTests: XCTestCase {

    // MARK: Viseme table

    func testVisemeTableRanges() {
        for viseme in Viseme.allCases {
            let s = viseme.shape
            XCTAssertGreaterThanOrEqual(s.open, 0, "\(viseme) open")
            XCTAssertLessThanOrEqual(s.open, 1, "\(viseme) open")
            XCTAssertGreaterThanOrEqual(s.width, -1, "\(viseme) width")
            XCTAssertLessThanOrEqual(s.width, 1, "\(viseme) width")
            XCTAssertEqual(s.smile, 0, "\(viseme) smile comes from the emotion, not the viseme")
            XCTAssertGreaterThanOrEqual(s.round, 0, "\(viseme) round")
            XCTAssertLessThanOrEqual(s.round, 1, "\(viseme) round")
            XCTAssertGreaterThanOrEqual(s.upperTeeth, 0)
            XCTAssertLessThanOrEqual(s.upperTeeth, 1)
            XCTAssertGreaterThanOrEqual(s.lowerTeeth, 0)
            XCTAssertLessThanOrEqual(s.lowerTeeth, 1)
            XCTAssertGreaterThanOrEqual(s.tongue, 0)
            XCTAssertLessThanOrEqual(s.tongue, 1)
            XCTAssertGreaterThanOrEqual(s.press, 0)
            XCTAssertLessThanOrEqual(s.press, 1)
            XCTAssertGreaterThan(viseme.nominalDuration, 0)
        }
        XCTAssertEqual(Viseme.sil.shape, .zero)
    }

    // MARK: Estimator

    func testEstimatorProducesVowelsForRussianAndEnglish() {
        let mama = TextVisemeEstimator.visemes(forWord: "мама", languageCode: "ru")
        XCTAssertFalse(mama.isEmpty)
        XCTAssertTrue(mama.contains { $0.viseme.isVowel })

        let hello = TextVisemeEstimator.visemes(forWord: "hello", languageCode: "en")
        XCTAssertFalse(hello.isEmpty)
        XCTAssertTrue(hello.contains { $0.viseme.isVowel })
        XCTAssertEqual(hello.map { $0.viseme }, [.kk, .e, .dd, .oh])

        // Keyframes are contiguous and start at zero.
        var cursor: TimeInterval = 0
        for kf in hello {
            XCTAssertEqual(kf.time, cursor, accuracy: 1e-9)
            XCTAssertGreaterThan(kf.duration, 0)
            cursor += kf.duration
        }
    }

    func testRussianWordsProduceSensibleSequences() {
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "мама", languageCode: "ru").map { $0.viseme },
                       [.pp, .aa, .pp, .aa])
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "привет", languageCode: "ru").map { $0.viseme },
                       [.pp, .rr, .ih, .ff, .e, .dd])
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "жили-были", languageCode: "ru").map { $0.viseme },
                       [.ch, .ih, .dd, .ih, .sil, .pp, .ih, .dd, .ih])
        // Capitalisation and the soft sign do not change the viseme sequence; the soft sign lengthens the consonant.
        let soft = TextVisemeEstimator.visemes(forWord: "Соль", languageCode: "ru")
        XCTAssertEqual(soft.map { $0.viseme }, [.ss, .oh, .dd])
        XCTAssertGreaterThan(soft[2].duration, Viseme.dd.nominalDuration)
        // Iotated vowel at a word start gets a short glide.
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "ёж", languageCode: "ru").map { $0.viseme }, [.ih, .oh, .ch])
        // Doubled letters merge.
        let doubled = TextVisemeEstimator.visemes(forWord: "Анна", languageCode: "ru")
        XCTAssertEqual(doubled.map { $0.viseme }, [.aa, .nn, .aa])
        XCTAssertGreaterThan(doubled[1].duration, Viseme.nn.nominalDuration)
    }

    func testEnglishDigraphsAndSilentE() {
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "the", languageCode: "en").map { $0.viseme }, [.th, .e])
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "ship", languageCode: "en").map { $0.viseme }, [.ch, .ih, .pp])
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "quick", languageCode: "en").map { $0.viseme }, [.kk, .ou, .ih, .kk])
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "like", languageCode: "en").map { $0.viseme }, [.dd, .ih, .kk])
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "sing", languageCode: "en").map { $0.viseme }, [.ss, .ih, .nn])
        // Unknown script degrades gracefully to an articulated pattern instead of nothing.
        let greek = TextVisemeEstimator.visemes(forWord: "αβγ", languageCode: "el")
        XCTAssertFalse(greek.isEmpty)
        XCTAssertTrue(greek.contains { $0.viseme.isVowel })
    }

    func testPunctuationYieldsSilencePauses() {
        let track = TextVisemeEstimator.track(for: "Привет, мир. Пока… Да!", languageCode: "ru", totalDuration: nil)
        let pauses = track.keyframes.filter { $0.viseme == .sil }.map { $0.duration }
        XCTAssertEqual(pauses.count, 4)
        XCTAssertTrue(pauses.contains { abs($0 - 0.18) < 1e-9 }, "comma pause")
        XCTAssertTrue(pauses.contains { abs($0 - 0.35) < 1e-9 }, "sentence pause")
        XCTAssertTrue(pauses.contains { abs($0 - 0.5) < 1e-9 }, "ellipsis pause")
        XCTAssertEqual(track.keyframes.last?.viseme, .sil, "trailing punctuation closes the mouth")

        let spaced = TextVisemeEstimator.track(for: "мама мыла", languageCode: "ru", totalDuration: nil)
        let spaces = spaced.keyframes.filter { $0.viseme == .sil }
        XCTAssertEqual(spaces.count, 1)
        XCTAssertEqual(spaces[0].duration, 0.04, accuracy: 1e-9)

        let dots = TextVisemeEstimator.track(for: "Ну... ладно", languageCode: "ru", totalDuration: nil)
        XCTAssertTrue(dots.keyframes.contains { $0.viseme == .sil && abs($0.duration - 0.5) < 1e-9 }, "three dots are an ellipsis")
        XCTAssertEqual(dots.wordOnsetTimes.count, 2)
    }

    // MARK: Track

    func testTrackSampleContinuity() {
        let text = "Жили-были дед да баба, и была у них курочка Ряба. Hello, wonderful world! Что это? Ух ты…"
        let track = TextVisemeEstimator.track(for: text, languageCode: nil, totalDuration: nil)
        XCTAssertGreaterThan(track.duration, 1)

        let step: TimeInterval = 1.0 / 120.0
        var t: TimeInterval = -0.1
        var previous = track.sample(at: t).mouth
        var maxDelta: Float = 0
        var maxOpen: Float = 0
        var maxEnergyDelta: Float = 0
        var previousEnergy = track.sample(at: t).energy
        while t < track.duration + 0.2 {
            t += step
            let s = track.sample(at: t)
            let diff = s.mouth.v - previous.v
            let channelDelta = max(diff.max(), (-diff).max())
            maxDelta = max(maxDelta, channelDelta)
            maxEnergyDelta = max(maxEnergyDelta, abs(s.energy - previousEnergy))
            maxOpen = max(maxOpen, s.mouth.open)
            XCTAssertEqual(s.mouth.smile, 0)
            XCTAssertGreaterThanOrEqual(s.mouth.open, 0)
            XCTAssertLessThanOrEqual(s.mouth.open, 1.0001)
            XCTAssertGreaterThanOrEqual(s.energy, 0)
            XCTAssertLessThanOrEqual(s.energy, 1)
            previous = s.mouth
            previousEnergy = s.energy
        }
        XCTAssertLessThan(maxDelta, 0.35, "coarticulation must not jump between 1/120 s frames")
        XCTAssertLessThan(maxEnergyDelta, 0.35)
        XCTAssertGreaterThan(maxOpen, 0.5, "vowels open the mouth")

        let after = track.sample(at: track.duration + 0.2)
        XCTAssertEqual(after.mouth, .zero)
        XCTAssertEqual(after.energy, 0)
        let before = track.sample(at: -0.5)
        XCTAssertEqual(before.mouth, .zero)
    }

    func testTrackSampleVowelPlateauAndSilence() {
        let track = LipSyncTrack(keyframes: TextVisemeEstimator.visemes(forWord: "мама", languageCode: "ru"))
        // Middle of the first "а".
        let aa = track.keyframes[1]
        let mid = track.sample(at: aa.time + aa.duration / 2)
        XCTAssertGreaterThan(mid.mouth.open, 0.6)
        XCTAssertGreaterThan(mid.energy, 0.6)
        // Middle of the first "м": lips pressed.
        let pp = track.keyframes[0]
        let pressed = track.sample(at: pp.time + pp.duration / 2)
        XCTAssertGreaterThan(pressed.mouth.press, 0.4)
        XCTAssertLessThan(pressed.mouth.open, 0.3)
        // Silence has zero energy.
        let silent = LipSyncTrack(keyframes: [VisemeKeyframe(time: 0, viseme: .sil, duration: 1, weight: 1)])
        let s = silent.sample(at: 0.5)
        XCTAssertEqual(s.energy, 0)
        XCTAssertEqual(s.mouth, .zero)
        XCTAssertEqual(LipSyncTrack.empty.sample(at: 0).energy, 0)
    }

    func testRetimedDuration() {
        let track = TextVisemeEstimator.track(for: "Привет, мир!", languageCode: "ru", totalDuration: nil)
        let retimed = track.retimed(toDuration: 2.0)
        XCTAssertEqual(retimed.duration, 2.0, accuracy: 1e-9)
        XCTAssertEqual(retimed.keyframes.count, track.keyframes.count)
        if let last = retimed.keyframes.last {
            XCTAssertEqual(last.time + last.duration, 2.0, accuracy: 1e-6)
        }
        let scale = 2.0 / track.duration
        for (a, b) in zip(track.keyframes, retimed.keyframes) {
            XCTAssertEqual(b.time, a.time * scale, accuracy: 1e-9)
            XCTAssertEqual(b.duration, a.duration * scale, accuracy: 1e-9)
            XCTAssertEqual(a.viseme, b.viseme)
        }
        // Passing totalDuration to the estimator is equivalent.
        let direct = TextVisemeEstimator.track(for: "Привет, мир!", languageCode: "ru", totalDuration: 2.0)
        XCTAssertEqual(direct.duration, 2.0, accuracy: 1e-9)
    }

    func testShiftedMovesKeyframes() {
        let track = LipSyncTrack(keyframes: TextVisemeEstimator.visemes(forWord: "hello", languageCode: "en"))
        let shifted = track.shifted(by: 0.5)
        XCTAssertEqual(shifted.keyframes.first?.time ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shifted.duration, track.duration + 0.5, accuracy: 1e-9)
        let a = track.sample(at: 0.1).mouth
        let b = shifted.sample(at: 0.6).mouth
        let diff = a.v - b.v
        XCTAssertLessThan(max(diff.max(), (-diff).max()), 1e-4, "shifting must not change the articulation")
    }

    func testTrackInitSortsKeyframes() {
        let unsorted = [
            VisemeKeyframe(time: 0.2, viseme: .aa, duration: 0.1, weight: 1),
            VisemeKeyframe(time: 0.0, viseme: .pp, duration: 0.2, weight: 1),
        ]
        let track = LipSyncTrack(keyframes: unsorted)
        XCTAssertEqual(track.keyframes.map { $0.viseme }, [.pp, .aa])
        XCTAssertEqual(track.duration, 0.3, accuracy: 1e-9)
        XCTAssertEqual(track.wordOnsetTimes, [0.0])
    }

    // MARK: Mixer

    func testMixerWordOnsetDecays() {
        let mixer = LipSyncMixer()
        XCTAssertFalse(mixer.isActive)
        let track = LipSyncTrack(keyframes: TextVisemeEstimator.visemes(forWord: "мама", languageCode: "ru"))
        mixer.schedule(track, startingAt: 10.0)
        XCTAssertTrue(mixer.isActive)

        let s0 = mixer.sample(at: 10.0)
        XCTAssertGreaterThan(s0.wordOnset, 0.95)
        XCTAssertTrue(s0.isSpeaking)
        let s1 = mixer.sample(at: 10.1)
        XCTAssertLessThan(s1.wordOnset, s0.wordOnset)
        XCTAssertGreaterThan(s1.wordOnset, 0)
        let s2 = mixer.sample(at: 10.3)
        XCTAssertEqual(s2.wordOnset, 0)

        // Long after the track ended the mixer is silent and inactive.
        let late = mixer.sample(at: 10.0 + track.duration + 1.0)
        XCTAssertEqual(late.mouth, .zero)
        XCTAssertFalse(late.isSpeaking)
        XCTAssertEqual(late.wordOnset, 0)
        XCTAssertFalse(mixer.isActive)
    }

    func testMixerClearAndReplace() {
        let mixer = LipSyncMixer()
        let track = LipSyncTrack(keyframes: TextVisemeEstimator.visemes(forWord: "привет", languageCode: "ru"))
        mixer.schedule(track, startingAt: 5.0)
        mixer.clear()
        XCTAssertFalse(mixer.isActive)
        XCTAssertFalse(mixer.sample(at: 5.1).isSpeaking)

        // A later schedule replaces the overlapping part of an earlier one.
        mixer.schedule(track, startingAt: 5.0)
        mixer.schedule(track, startingAt: 5.2)
        let mid = mixer.sample(at: 5.25)
        XCTAssertTrue(mid.isSpeaking)
        XCTAssertLessThanOrEqual(mid.mouth.open, 1.0001)
        XCTAssertFalse(mixer.sample(at: 5.2 + track.duration + 0.5).isSpeaking)
    }

    func testMixerOutputIsSmoothAtSixtyFps() {
        let mixer = LipSyncMixer()
        // Squeeze a word into a very short gap: the slew limiter must still keep frames continuous.
        let squeezed = LipSyncTrack(keyframes: TextVisemeEstimator.visemes(forWord: "привет", languageCode: "ru")).retimed(toDuration: 0.12)
        mixer.schedule(squeezed, startingAt: 1.0)
        var t: TimeInterval = 0.9
        var previous = mixer.sample(at: t).mouth
        var maxDelta: Float = 0
        while t < 1.5 {
            t += 1.0 / 60.0
            let s = mixer.sample(at: t)
            let diff = s.mouth.v - previous.v
            maxDelta = max(maxDelta, max(diff.max(), (-diff).max()))
            previous = s.mouth
        }
        XCTAssertLessThan(maxDelta, 0.35)
    }

    // MARK: Timed transcript

    func testTimedTranscriptDriverMapsWordsToTime() {
        let words = [
            TimedWord(text: "Мама", start: 0.0, end: 0.5),
            TimedWord(text: "мыла", start: 1.0, end: 1.5),
            TimedWord(text: "раму.", start: 2.0, end: 2.6),
        ]
        let driver = TimedTranscriptDriver(words: words, languageCode: "ru")
        XCTAssertFalse(driver.isRunning)
        XCTAssertEqual(driver.sample(at: 100.2), .silent)

        driver.start(at: 100.0)
        XCTAssertTrue(driver.isRunning)
        let first = driver.sample(at: 100.17)   // inside the first "а" of "Мама"
        XCTAssertTrue(first.isSpeaking)
        XCTAssertGreaterThan(first.mouth.open, 0.3)
        XCTAssertGreaterThan(first.energy, 0.3)

        let gap = driver.sample(at: 100.75)      // between the first and second word
        XCTAssertFalse(gap.isSpeaking)
        XCTAssertLessThan(gap.mouth.open, 0.05)

        let second = driver.sample(at: 101.15)   // inside "мыла"
        XCTAssertTrue(second.isSpeaking)
        XCTAssertGreaterThan(second.energy, 0.2)

        let onset = driver.sample(at: 102.0)     // onset of the third word
        XCTAssertGreaterThan(onset.wordOnset, 0.9)

        let after = driver.sample(at: 104.0)
        XCTAssertFalse(after.isSpeaking)
        XCTAssertEqual(after.mouth, .zero)

        driver.stop()
        XCTAssertFalse(driver.isRunning)
        XCTAssertEqual(driver.sample(at: 101.15), .silent)
    }

    // MARK: Language detection

    func testDetectLanguage() {
        XCTAssertEqual(TextVisemeEstimator.detectLanguage(of: "Привет, мир!"), "ru")
        XCTAssertEqual(TextVisemeEstimator.detectLanguage(of: "Hello, world!"), "en")
        XCTAssertEqual(TextVisemeEstimator.detectLanguage(of: "Hello, мир"), "ru")
        XCTAssertEqual(TextVisemeEstimator.detectLanguage(of: ""), "en")
        XCTAssertEqual(TextVisemeEstimator.detectLanguage(of: "123 !?"), "en")
        XCTAssertEqual(TextVisemeEstimator.detectLanguage(of: "Ёлка"), "ru")
    }

    // MARK: Audio level driver (no audio hardware)

    func testAudioLevelDriverIsSilentWithoutInput() {
        let driver = AudioLevelDriver()
        let a = driver.sample(at: 1.0)
        XCTAssertEqual(a.mouth, .zero)
        XCTAssertEqual(a.energy, 0)
        XCTAssertFalse(a.isSpeaking)
        XCTAssertEqual(a.wordOnset, 0)
        let b = driver.sample(at: 1.5)
        XCTAssertEqual(b.mouth, .zero)
        XCTAssertFalse(b.isSpeaking)
        driver.detach()   // no tap installed: must be a no-op
        driver.reset()
        XCTAssertEqual(driver.sample(at: 2.0).energy, 0)
    }

    func testAudioLevelDriverRespondsToIngestedBuffer() {
        let driver = AudioLevelDriver()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024),
              let channel = buffer.floatChannelData else {
            XCTFail("could not create a PCM buffer")
            return
        }
        buffer.frameLength = 1024
        // A loud 220 Hz tone.
        for i in 0..<1024 {
            channel[0][i] = 0.5 * sin(Float(i) * 2 * Float.pi * 220 / 48_000)
        }
        driver.ingest(buffer)
        // The analysis is stamped with CACurrentMediaTime, so sample on the same clock.
        let now = CACurrentMediaTime()
        var s = driver.sample(at: now)
        var t = now
        for _ in 0..<12 {
            t += 1.0 / 60.0
            s = driver.sample(at: t)
        }
        XCTAssertGreaterThan(s.mouth.open, 0.1)
        XCTAssertGreaterThan(s.energy, 0.1)
        XCTAssertTrue(s.isSpeaking)
        XCTAssertEqual(s.mouth.smile, 0)
    }
}
