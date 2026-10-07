import Foundation

/// One-shot animations layered on top of the current emotion. Implemented in `Core/Animation/Gestures.swift`.
public enum Gesture: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    /// "Yes" — two quick head nods.
    case nod
    /// "No" — head shake.
    case shake
    /// Happy hop with squash & stretch.
    case bounce
    /// Wave with the right arm (left for designs without arms: whole-body sway).
    case wave
    /// Gaze up-right, brow asymmetry, hand to chin, question mark fades in.
    case think
    /// Surprise pop: eyes wide, body scale punch, exclamation mark.
    case surprisePop
    /// Turns away, blushes, peeks back.
    case shy
    /// Spin / jump with a sparkle burst and hearts.
    case celebrate
    /// Right eye wink with a smile.
    case wink
    /// Big slow yawn (mouth wide, eyes closed, stretch).
    case yawn
    /// Leans in, eyes widen, as if peeking at the viewer.
    case peek
    /// Giggle: fast small bounces, eyes squint, mouth smiles.
    case giggle
    /// Falls asleep: slow blink-out, droops, zzz.
    case sleep
    /// Wakes up: eyes pop open, shake, stretch.
    case wakeUp

    public var id: String { rawValue }

    /// Approximate duration in seconds (the gesture may be stretched by the energy of the current emotion).
    public var nominalDuration: TimeInterval {
        switch self {
        case .nod: return 0.9
        case .shake: return 0.9
        case .bounce: return 0.8
        case .wave: return 1.6
        case .think: return 2.4
        case .surprisePop: return 1.0
        case .shy: return 2.2
        case .celebrate: return 1.8
        case .wink: return 0.8
        case .yawn: return 2.6
        case .peek: return 1.6
        case .giggle: return 1.4
        case .sleep: return 2.5
        case .wakeUp: return 1.4
        }
    }

    public var englishName: String {
        switch self {
        case .nod: return "Nod"
        case .shake: return "Shake head"
        case .bounce: return "Bounce"
        case .wave: return "Wave"
        case .think: return "Think"
        case .surprisePop: return "Surprise!"
        case .shy: return "Shy"
        case .celebrate: return "Celebrate"
        case .wink: return "Wink"
        case .yawn: return "Yawn"
        case .peek: return "Peek"
        case .giggle: return "Giggle"
        case .sleep: return "Fall asleep"
        case .wakeUp: return "Wake up"
        }
    }

    public var russianName: String {
        switch self {
        case .nod: return "Кивок"
        case .shake: return "Нет-нет"
        case .bounce: return "Прыжок"
        case .wave: return "Помахать"
        case .think: return "Подумать"
        case .surprisePop: return "Ой!"
        case .shy: return "Смутиться"
        case .celebrate: return "Ура!"
        case .wink: return "Подмигнуть"
        case .yawn: return "Зевнуть"
        case .peek: return "Подглядеть"
        case .giggle: return "Хихикнуть"
        case .sleep: return "Уснуть"
        case .wakeUp: return "Проснуться"
        }
    }

    public func displayName(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        languageCode == "ru" ? russianName : englishName
    }
}
