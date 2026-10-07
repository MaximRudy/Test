import Foundation

/// The eight playable characters. The first four come from stand-alone references,
/// the last four form the "Elementals" family that shares one rig with four skins.
public enum CharacterKind: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    /// Reference 1 — golden five-point star in an indigo star-speckled hood, holding a glowing book and a pencil-wand.
    case lumi
    /// Reference 2 — translucent golden flame-drop with a lavender brain on its forehead, tiny arms and feet.
    case spark
    /// Reference 3 — magenta→violet→blue hooded wisp with a dark face, huge galaxy eyes and a crescent moon mark.
    case nox
    /// Reference 4 — small warm flame sprite living inside a glass bell jar on a wooden base, surrounded by fireflies.
    case lumie
    /// Reference 5a — fire elemental: orange flame with waving tongues.
    case ember
    /// Reference 5b — water elemental: blue jelly teardrop.
    case drop
    /// Reference 5c — air elemental: fluffy white cloud with a curl.
    case puff
    /// Reference 5d — earth elemental: round brown body with a green cap and two leaves.
    case sprout

    public var id: String { rawValue }

    public var isElemental: Bool {
        switch self {
        case .ember, .drop, .puff, .sprout: return true
        default: return false
        }
    }

    public var englishName: String {
        switch self {
        case .lumi: return "Lumi"
        case .spark: return "Spark"
        case .nox: return "Nox"
        case .lumie: return "Lumie"
        case .ember: return "Ember"
        case .drop: return "Drop"
        case .puff: return "Puff"
        case .sprout: return "Sprout"
        }
    }

    public var russianName: String {
        switch self {
        case .lumi: return "Луми"
        case .spark: return "Искорка"
        case .nox: return "Нокс"
        case .lumie: return "Люми"
        case .ember: return "Уголёк"
        case .drop: return "Капелька"
        case .puff: return "Пушинка"
        case .sprout: return "Росток"
        }
    }

    /// Localized display name. Defaults to the current locale's language.
    public func displayName(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        languageCode == "ru" ? russianName : englishName
    }

    /// Characters in presentation order for pickers.
    public static let presentationOrder: [CharacterKind] = [.lumi, .spark, .nox, .lumie, .ember, .drop, .puff, .sprout]
}
