import Foundation

/// 15-viseme set (the Oculus/OVR LipSync inventory), expressive enough for Russian and English.
/// Each viseme maps to a full `MouthShape` (jaw, width, rounding, teeth, tongue, lip press) —
/// speech is articulated, not just "mouth opens and closes".
public enum Viseme: Int, CaseIterable, Codable, Sendable, Hashable {
    /// Silence / rest.
    case sil = 0
    /// p, b, m — lips pressed together.
    case pp
    /// f, v — upper teeth on lower lip.
    case ff
    /// th (English) — tongue between teeth.
    case th
    /// d, t, l — jaw slightly open, tongue up.
    case dd
    /// k, g, h, х — open mid, back of tongue.
    case kk
    /// ch, sh, zh, щ, j — lips pushed forward, slightly rounded.
    case ch
    /// s, z, ц — teeth together, wide.
    case ss
    /// n, ng — like dd with the tongue visible.
    case nn
    /// r — small rounded opening.
    case rr
    /// a (а, я) — wide open.
    case aa
    /// e (э, е) — mid open, wide.
    case e
    /// i (и, ы, й) — narrow opening, very wide.
    case ih
    /// o (о, ё) — round, open.
    case oh
    /// u (у, ю, w) — tight round.
    case ou

    public var isVowel: Bool {
        switch self {
        case .aa, .e, .ih, .oh, .ou: return true
        default: return false
        }
    }

    /// Typical duration of this viseme in conversational speech (seconds). Drivers scale these to real timing.
    public var nominalDuration: TimeInterval {
        switch self {
        case .sil: return 0.08
        case .aa, .oh: return 0.13
        case .e, .ih, .ou: return 0.11
        default: return 0.065
        }
    }

    /// Mouth articulation for the viseme at full weight. `smile` is 0 here — it is added from the emotion.
    public var shape: MouthShape {
        switch self {
        case .sil: return MouthShape(open: 0.00, width: 0.00, smile: 0, round: 0.00, upperTeeth: 0.00, lowerTeeth: 0.00, tongue: 0.00, press: 0.00)
        case .pp:  return MouthShape(open: 0.00, width: 0.10, smile: 0, round: 0.10, upperTeeth: 0.00, lowerTeeth: 0.00, tongue: 0.00, press: 1.00)
        case .ff:  return MouthShape(open: 0.15, width: 0.30, smile: 0, round: 0.00, upperTeeth: 0.90, lowerTeeth: 0.00, tongue: 0.00, press: 0.30)
        case .th:  return MouthShape(open: 0.25, width: 0.20, smile: 0, round: 0.00, upperTeeth: 0.40, lowerTeeth: 0.10, tongue: 0.90, press: 0.00)
        case .dd:  return MouthShape(open: 0.30, width: 0.30, smile: 0, round: 0.00, upperTeeth: 0.60, lowerTeeth: 0.00, tongue: 0.50, press: 0.00)
        case .kk:  return MouthShape(open: 0.40, width: 0.10, smile: 0, round: 0.10, upperTeeth: 0.20, lowerTeeth: 0.00, tongue: 0.00, press: 0.00)
        case .ch:  return MouthShape(open: 0.30, width: -0.20, smile: 0, round: 0.60, upperTeeth: 0.50, lowerTeeth: 0.00, tongue: 0.00, press: 0.00)
        case .ss:  return MouthShape(open: 0.15, width: 0.60, smile: 0, round: 0.00, upperTeeth: 0.90, lowerTeeth: 0.70, tongue: 0.00, press: 0.00)
        case .nn:  return MouthShape(open: 0.25, width: 0.30, smile: 0, round: 0.00, upperTeeth: 0.50, lowerTeeth: 0.00, tongue: 0.60, press: 0.00)
        case .rr:  return MouthShape(open: 0.30, width: -0.30, smile: 0, round: 0.50, upperTeeth: 0.30, lowerTeeth: 0.00, tongue: 0.30, press: 0.00)
        case .aa:  return MouthShape(open: 0.95, width: 0.30, smile: 0, round: 0.10, upperTeeth: 0.30, lowerTeeth: 0.20, tongue: 0.30, press: 0.00)
        case .e:   return MouthShape(open: 0.50, width: 0.70, smile: 0, round: 0.00, upperTeeth: 0.60, lowerTeeth: 0.30, tongue: 0.00, press: 0.00)
        case .ih:  return MouthShape(open: 0.30, width: 0.90, smile: 0, round: 0.00, upperTeeth: 0.70, lowerTeeth: 0.40, tongue: 0.00, press: 0.00)
        case .oh:  return MouthShape(open: 0.70, width: -0.40, smile: 0, round: 0.80, upperTeeth: 0.10, lowerTeeth: 0.00, tongue: 0.10, press: 0.00)
        case .ou:  return MouthShape(open: 0.35, width: -0.80, smile: 0, round: 1.00, upperTeeth: 0.00, lowerTeeth: 0.00, tongue: 0.00, press: 0.10)
        }
    }
}
