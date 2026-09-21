import Foundation

/// A calendar day with no time zone — 2026-09-21 — the key a planned meal is stored under.
/// Encodes as its ISO string, which sorts chronologically, so it doubles as a SwiftData attribute.
public struct PlanDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strictly "yyyy-MM-dd"; nil for anything else, including impossible dates such as 2026-02-30.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return nil
        }
        let candidate = PlanDay(year: year, month: month, day: day)
        // Round-trip through a calendar to reject impossible dates.
        guard let date = Self.utc.date(from: candidate.components), PlanDay(date, calendar: Self.utc) == candidate else {
            return nil
        }
        self = candidate
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The start of this day in `calendar`'s time zone.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// Calendar arithmetic, so a clock change never shifts the result by a day.
    public func adding(days: Int, calendar: Calendar = .current) -> PlanDay {
        guard days != 0, let moved = calendar.date(byAdding: .day, value: days, to: date(in: calendar)) else { return self }
        return PlanDay(moved, calendar: calendar)
    }

    public static func < (lhs: PlanDay, rhs: PlanDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Codable (single ISO string)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = PlanDay(isoString: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a yyyy-MM-dd date: \(text)")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    // MARK: Private

    private var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
