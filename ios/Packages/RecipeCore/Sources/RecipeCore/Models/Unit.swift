import Foundation

/// The units the extractor may emit (SPEC §5). Raw values are the wire strings shared with the Worker's Zod schema.
public enum Unit: String, Codable, CaseIterable, Hashable, Sendable {
    // mass
    case g, kg, oz, lb
    // volume
    case ml, l, tsp, tbsp, cup, flOz = "fl_oz", pint
    // count
    case each, clove, tin, jar, packet, bunch, sprig, slice, sheet, stick, bulb, head
    // vague
    case pinch, dash, handful, splash

    public enum Kind: Sendable {
        case mass, volume, count, vague
    }

    public var kind: Kind {
        switch self {
        case .g, .kg, .oz, .lb:
            return .mass
        case .ml, .l, .tsp, .tbsp, .cup, .flOz, .pint:
            return .volume
        case .each, .clove, .tin, .jar, .packet, .bunch, .sprig, .slice, .sheet, .stick, .bulb, .head:
            return .count
        case .pinch, .dash, .handful, .splash:
            return .vague
        }
    }

    /// Symbols that are never pluralised: g, kg, oz, lb, ml, l, tsp, tbsp, fl oz (SPEC §7).
    public var isAbbreviation: Bool {
        switch self {
        case .g, .kg, .oz, .lb, .ml, .l, .tsp, .tbsp, .flOz:
            return true
        default:
            return false
        }
    }

    /// The word shown after an amount: "g", "fl oz", "tin"/"tins", "pinch"/"pinches". Empty for `.each`.
    public func displayName(plural: Bool) -> String {
        switch self {
        case .flOz:
            return "fl oz"
        case .each:
            return ""
        case _ where isAbbreviation:
            return rawValue
        case .pinch, .dash, .splash, .bunch:
            return plural ? rawValue + "es" : rawValue
        default:
            return plural ? rawValue + "s" : rawValue
        }
    }
}
