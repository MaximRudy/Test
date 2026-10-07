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
        // iOS taps deliver ~100 ms buffers: a loud 220 Hz tone.
        guard let buffer = LipSyncTests.toneBuffer(frequency: 220, sampleRate: 48_000, frames: 4_800, amplitude: 0.5) else {
            XCTFail("could not create a PCM buffer")
            return
        }
        driver.ingest(buffer)
        // The blocks are replayed on the CACurrentMediaTime clock from the moment the buffer arrived.
        let now = CACurrentMediaTime()
        var s = driver.sample(at: now)
        var t = now
        for _ in 0..<3 {
            t += 1.0 / 60.0
            s = driver.sample(at: t)
        }
        XCTAssertGreaterThan(s.mouth.open, 0.1)
        XCTAssertGreaterThan(s.energy, 0.1)
        XCTAssertTrue(s.isSpeaking)
        XCTAssertEqual(s.mouth.smile, 0)

        // No further buffers: once the queued 100 ms have played the input is silence and the mouth closes.
        while t < now + 1.0 {
            t += 1.0 / 60.0
            s = driver.sample(at: t)
        }
        XCTAssertLessThan(s.mouth.open, 0.01)
        XCTAssertLessThan(s.energy, 0.01)
        XCTAssertFalse(s.isSpeaking)
    }

    func testAudioLevelDriverBrightnessDoesNotDependOnSampleRate() {
        var widths: [Float] = []
        var rounds: [Float] = []
        for rate in [16_000.0, 48_000.0] {
            let driver = AudioLevelDriver()
            guard let buffer = LipSyncTests.toneBuffer(frequency: 1_000, sampleRate: rate, frames: Int(rate * 0.1), amplitude: 0.5) else {
                XCTFail("could not create a PCM buffer")
                return
            }
            driver.ingest(buffer)
            let s = driver.sample(at: CACurrentMediaTime())
            widths.append(s.mouth.width)
            rounds.append(s.mouth.round)
        }
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.1, "the same sound must give the same vowel colour at any sample rate")
        XCTAssertEqual(rounds[0], rounds[1], accuracy: 0.1)
    }

    func testSpectralCentroidIsMeasuredInHertz() {
        let analyzer = SpectralCentroidAnalyzer()
        for rate in [16_000.0, 44_100.0, 48_000.0] {
            guard let buffer = LipSyncTests.toneBuffer(frequency: 1_000, sampleRate: rate, frames: 2_048, amplitude: 0.5),
                  let channels = buffer.floatChannelData else {
                XCTFail("could not create a PCM buffer")
                return
            }
            let centroid = analyzer.centroid(of: channels, channelCount: 1, stride: buffer.stride, endFrame: 2_048, sampleRate: rate)
            XCTAssertEqual(centroid, 1_000, accuracy: 120, "1 kHz tone at \(rate) Hz")
        }
        guard let silence = LipSyncTests.toneBuffer(frequency: 1_000, sampleRate: 48_000, frames: 1_024, amplitude: 0),
              let silentChannels = silence.floatChannelData else {
            XCTFail("could not create a PCM buffer")
            return
        }
        XCTAssertEqual(analyzer.centroid(of: silentChannels, channelCount: 1, stride: silence.stride, endFrame: 1_024, sampleRate: 48_000), 0)
        // Back vowels (dark) → 0, front vowels and fricatives (bright) → 1.
        XCTAssertEqual(AudioLevelTuning.brightness(forCentroid: 300), 0)
        XCTAssertEqual(AudioLevelTuning.brightness(forCentroid: 4_000), 1)
        XCTAssertLessThan(AudioLevelTuning.brightness(forCentroid: 770), 0.15)
        XCTAssertGreaterThan(AudioLevelTuning.brightness(forCentroid: 1_500), 0.8)
    }

    func testAudioBlockRingReplaysBlocksOnTheClock() {
        var ring = AudioBlockRing()
        var levels = SIMD64<Float>(repeating: 0)
        let centroids = SIMD64<Float>(repeating: 1_000)
        for i in 0..<10 { levels[i] = Float(i + 1) * 0.01 }
        ring.enqueue(levels: levels, centroids: centroids, count: 10, blockDuration: 0.01, bufferDuration: 0.1, now: 5.0)
        XCTAssertFalse(ring.lookup(at: 4.99, tolerance: 0.03).isFresh, "nothing before the first block")
        XCTAssertEqual(ring.lookup(at: 5.0, tolerance: 0.03).level, 0.01, accuracy: 1e-6)
        XCTAssertEqual(ring.lookup(at: 5.055, tolerance: 0.03).level, 0.06, accuracy: 1e-6)
        XCTAssertEqual(ring.lookup(at: 5.055, tolerance: 0.03).centroid, 1_000)
        XCTAssertTrue(ring.lookup(at: 5.12, tolerance: 0.03).isFresh)
        XCTAssertFalse(ring.lookup(at: 5.14, tolerance: 0.03).isFresh, "stale 30 ms after the queued audio ends")

        // A buffer that arrives on time continues seamlessly after the previous one.
        ring.enqueue(levels: levels, centroids: centroids, count: 10, blockDuration: 0.01, bufferDuration: 0.1, now: 5.098)
        XCTAssertEqual(ring.end, 5.2, accuracy: 1e-6)
        XCTAssertEqual(ring.lookup(at: 5.105, tolerance: 0.03).level, 0.01, accuracy: 1e-6)
        XCTAssertEqual(ring.lookup(at: 5.095, tolerance: 0.03).level, 0.10, accuracy: 1e-6)

        // Capacity is bounded; a feed faster than real time resynchronises to `now`.
        for k in 0..<20 {
            ring.enqueue(levels: levels, centroids: centroids, count: 10, blockDuration: 0.01, bufferDuration: 0.1, now: 5.2 + Double(k) * 0.1)
        }
        XCTAssertLessThanOrEqual(ring.count, AudioBlockRing.capacity)
        let earlyArrival = ring.end - 0.2
        ring.enqueue(levels: levels, centroids: centroids, count: 10, blockDuration: 0.01, bufferDuration: 0.1, now: earlyArrival)
        XCTAssertEqual(ring.end, earlyArrival + 0.1, accuracy: 1e-6)
        XCTAssertEqual(ring.lookup(at: earlyArrival, tolerance: 0.03).level, 0.01, accuracy: 1e-6)
        ring.removeAll()
        XCTAssertFalse(ring.lookup(at: 5.0, tolerance: 0.03).isFresh)
    }

    // MARK: TTS word timing

    func testSpeechTimingIgnoresPunctuationPauses() {
        let text = "Дед бил, бил, не разбил." as NSString
        let words = ["Дед", "бил", "бил", "не", "разбил"]
        let secondsPerLetter: TimeInterval = 0.08
        let commaPause: TimeInterval = 0.25
        var timer = SpeechWordTimer()
        timer.begin(languageCode: "ru-RU", effectiveRate: 1)
        let mixer = LipSyncMixer()

        var t: TimeInterval = 100
        var searchFrom = 0
        var lastStart: TimeInterval = 0
        var lastSpokenEnd: TimeInterval = 0
        var maxStretch: TimeInterval = 0
        for word in words {
            let range = text.range(of: word, options: [], range: NSRange(location: searchFrom, length: text.length - searchFrom))
            XCTAssertNotEqual(range.location, NSNotFound)
            searchFrom = range.location + range.length
            let boundary = SpeechWordTimer.boundary(after: searchFrom, in: text)
            let spoken = TimeInterval(word.count) * secondsPerLetter
            let reported = timer.handleWord(in: text, location: range.location, length: range.length,
                                            languageCode: "ru-RU", at: t, mixer: mixer)
            XCTAssertEqual(reported, word)
            let estimated = timer.estimatedDuration(letters: word.count, boundary: boundary)
            maxStretch = max(maxStretch, estimated / spoken)
            lastStart = t
            lastSpokenEnd = t + spoken
            // Synthetic TTS: letters at a constant rate, a space, and a pause after punctuation.
            t += spoken + secondsPerLetter + (boundary.hasPause ? commaPause : 0)
        }
        XCTAssertLessThanOrEqual(maxStretch, 1.2, "pauses must not slow the viseme estimate down")
        XCTAssertEqual(timer.secondsPerCharacter, secondsPerLetter, accuracy: 0.01)

        // Play the schedule at 60 fps: the last word articulates, then the mouth is shut 120 ms after it ends.
        var time: TimeInterval = 99.9
        var sample = mixer.sample(at: time)
        var maxOpenInLastWord: Float = 0
        let closeBy = lastSpokenEnd + 0.12
        while time < closeBy {
            time = min(time + 1.0 / 60.0, closeBy)
            sample = mixer.sample(at: time)
            if time >= lastStart && time <= lastSpokenEnd {
                maxOpenInLastWord = max(maxOpenInLastWord, sample.mouth.open)
            }
        }
        XCTAssertGreaterThan(maxOpenInLastWord, 0.3)
        XCTAssertLessThan(sample.mouth.open, 0.05, "sentence-final punctuation closes the mouth within 120 ms")
    }

    func testSpeechWordBoundaryScan() {
        let text = "Кто там? Я, кот — и всё. Жили-были" as NSString
        func end(of word: String) -> Int {
            let range = text.range(of: word)
            return range.location + range.length
        }
        let question = SpeechWordTimer.boundary(after: end(of: "там"), in: text)
        XCTAssertTrue(question.isQuestion)
        XCTAssertTrue(question.endsSentence)
        XCTAssertTrue(question.hasPause)
        let comma = SpeechWordTimer.boundary(after: end(of: "Я"), in: text)
        XCTAssertTrue(comma.hasPause)
        XCTAssertFalse(comma.endsSentence)
        XCTAssertTrue(SpeechWordTimer.boundary(after: end(of: "кот"), in: text).hasPause, "spaced dash")
        XCTAssertTrue(SpeechWordTimer.boundary(after: end(of: "всё"), in: text).endsSentence)
        XCTAssertFalse(SpeechWordTimer.boundary(after: end(of: "Жили"), in: text).hasPause, "in-word hyphen")
        XCTAssertEqual(SpeechWordTimer.boundary(after: end(of: "Кто"), in: text), SpeechWordTimer.Boundary())
        XCTAssertEqual(SpeechWordTimer.boundary(after: text.length, in: text), SpeechWordTimer.Boundary())

        // Some voices include the punctuation in the word range: it still counts as the boundary.
        let attached = "Ты кто?" as NSString
        let wordEnd = SpeechWordTimer.articulationEnd(in: attached, location: 3, length: 4)
        XCTAssertEqual(wordEnd, 6)
        XCTAssertTrue(SpeechWordTimer.boundary(after: wordEnd, in: attached).isQuestion)
        XCTAssertEqual(SpeechWordTimer.articulationEnd(in: attached, location: 0, length: 2), 2)
    }

    func testVoiceLanguageMatching() {
        XCTAssertEqual(SpeechSynthesisDriver.baseLanguage(of: "en-US"), "en")
        XCTAssertEqual(SpeechSynthesisDriver.baseLanguage(of: "ru_RU"), "ru")
        XCTAssertEqual(SpeechSynthesisDriver.baseLanguage(of: "RU"), "ru")
        XCTAssertEqual(SpeechSynthesisDriver.bcp47(for: "en"), "en-US")
        XCTAssertEqual(SpeechSynthesisDriver.bcp47(for: "ru"), "ru-RU")
        XCTAssertEqual(SpeechSynthesisDriver.bcp47(for: "en_GB"), "en-GB")
    }

    func testSpeechAudioSessionIsSharedAndReferenceCounted() {
        // Bookkeeping only: the platform AVAudioSession is not touched.
        let saved = SpeechAudioSession.controlsPlatformSession
        SpeechAudioSession.controlsPlatformSession = false
        defer { SpeechAudioSession.controlsPlatformSession = saved }
        let baseline = SpeechAudioSession.userCount

        // Two drivers speak: one activation, kept while either of them still holds the session.
        SpeechAudioSession.acquire()
        SpeechAudioSession.acquire()
        XCTAssertEqual(SpeechAudioSession.userCount, baseline + 2)
        XCTAssertTrue(SpeechAudioSession.isActive)
        SpeechAudioSession.release()
        XCTAssertEqual(SpeechAudioSession.userCount, baseline + 1)
        XCTAssertTrue(SpeechAudioSession.isActive)
        XCTAssertFalse(SpeechAudioSession.isDeactivationPending, "another driver is still speaking")

        // The last holder lets go: deactivation is deferred, and the next speaker cancels it.
        SpeechAudioSession.release()
        XCTAssertEqual(SpeechAudioSession.userCount, baseline)
        if baseline == 0 {
            XCTAssertTrue(SpeechAudioSession.isDeactivationPending)
        }
        SpeechAudioSession.acquire()
        XCTAssertFalse(SpeechAudioSession.isDeactivationPending)
        XCTAssertTrue(SpeechAudioSession.isActive)
        SpeechAudioSession.release()
        XCTAssertEqual(SpeechAudioSession.userCount, baseline)

        // Unbalanced releases never underflow.
        if baseline == 0 {
            SpeechAudioSession.release()
            XCTAssertEqual(SpeechAudioSession.userCount, 0)
        }
    }

    func testIdleSpeechDriverHoldsNoAudioSession() {
        let baseline = SpeechAudioSession.userCount
        let driver = SpeechSynthesisDriver()
        driver.stop()
        driver.resume()
        driver.pause()
        XCTAssertFalse(driver.isSpeaking)
        XCTAssertEqual(SpeechAudioSession.userCount, baseline, "stop() without an utterance must not release someone else's hold")
        XCTAssertEqual(driver.sample(at: 1.0), .silent)
    }

    // MARK: Estimator details

    func testRussianStressMarksAreIgnored() {
        func v(_ word: String) -> [Viseme] {
            TextVisemeEstimator.visemes(forWord: word, languageCode: "ru").map { $0.viseme }
        }
        XCTAssertEqual(v("Жи\u{301}ли"), [.ch, .ih, .dd, .ih])
        XCTAssertEqual(v("молоко\u{301}"), v("молоко"))
        XCTAssertEqual(v("молоко"), [.pp, .oh, .dd, .oh, .kk, .oh])
        XCTAssertEqual(v("мо\u{301}й"), [.pp, .oh, .ih], "the breve of й survives")
        XCTAssertEqual(v("\u{450}ж"), v("еж"))
        XCTAssertEqual(TextVisemeEstimator.articulatedLength(of: "жи\u{301}ли"), 4)
        // Accents on Latin letters are not stress marks.
        XCTAssertEqual(TextVisemeEstimator.visemes(forWord: "café", languageCode: "en").map { $0.viseme }, [.kk, .aa, .ff, .e])
    }

    func testEnglishSilentLettersAndRoundedOu() {
        func v(_ word: String) -> [Viseme] {
            TextVisemeEstimator.visemes(forWord: word, languageCode: "en").map { $0.viseme }
        }
        XCTAssertEqual(v("night"), [.nn, .ih, .dd])
        XCTAssertEqual(v("knight"), [.nn, .ih, .dd])
        XCTAssertEqual(v("write"), [.rr, .ih, .dd])
        XCTAssertEqual(v("lamb"), [.dd, .aa, .pp])
        XCTAssertEqual(v("you"), [.ih, .ou])
        XCTAssertEqual(v("could"), [.kk, .ou, .dd, .dd])
        XCTAssertEqual(v("thought"), [.th, .oh, .dd])
        XCTAssertEqual(v("laugh"), [.dd, .oh, .ff])
        XCTAssertEqual(v("ghost"), [.kk, .oh, .ss, .dd])
        XCTAssertEqual(v("house"), [.kk, .aa, .ou, .ss])
        XCTAssertFalse(v("though").contains(.ff))
    }

    // MARK: Mixer details

    func testMixerSpeakingTailBridgesShortGaps() {
        let mixer = LipSyncMixer()
        let word = LipSyncTrack(keyframes: TextVisemeEstimator.visemes(forWord: "мама", languageCode: "ru"))
        mixer.schedule(word, startingAt: 10.0)
        let gapStart = 10.0 + word.duration
        mixer.schedule(word, startingAt: gapStart + 0.2)
        XCTAssertTrue(mixer.sample(at: gapStart + 0.1).isSpeaking, "short gaps between words keep isSpeaking")
        XCTAssertFalse(mixer.sample(at: gapStart + 0.15).isSpeaking)
        XCTAssertTrue(mixer.sample(at: gapStart + 0.25).isSpeaking)
    }

    func testQuestionEmphasisHoldsEnergyThroughTheWord() {
        let track = LipSyncTrack(keyframes: TextVisemeEstimator.visemes(forWord: "мама", languageCode: "ru"))
        let plain = LipSyncMixer()
        plain.schedule(track, startingAt: 10, energyGain: 1)
        let question = LipSyncMixer()
        question.schedule(track, startingAt: 10, energyGain: SpeechWordTimer.questionEnergyGain)
        // Middle of the first "м" (lips pressed): normally low energy, held high for the last word of a question.
        let mid = 10 + track.keyframes[0].duration / 2
        XCTAssertLessThan(plain.sample(at: mid).energy, 0.6)
        XCTAssertGreaterThan(question.sample(at: mid).energy, 0.85)
        XCTAssertEqual(question.sample(at: 10 + track.duration + 0.2).energy, 0)
    }

    // MARK: Helpers

    private static func toneBuffer(frequency: Double, sampleRate: Double, frames: Int, amplitude: Float) -> AVAudioPCMBuffer? {
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames {
            channel[0][i] = amplitude * Float(sin(Double(i) * 2 * Double.pi * frequency / sampleRate))
        }
        return buffer
    }
}
