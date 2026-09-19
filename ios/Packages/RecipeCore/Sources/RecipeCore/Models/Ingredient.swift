import Foundation

/// How sure the extractor was about a row. Low-confidence rows are highlighted in review (SPEC §3).
public enum Confidence: String, Codable, Hashable, Sendable {
    case high, low
}

/// "1 x 400g tin" → `PackageSize(quantity: 400, unit: .g)`. Mass or volume only; the Worker validates that.
public struct PackageSize: Codable, Hashable, Sendable {
    public var quantity: Double
    public var unit: Unit

    public init(quantity: Double, unit: Unit) {
        self.quantity = quantity
        self.unit = unit
    }
}

/// One ingredient row as extracted (SPEC §5). Wire keys are the property names.
public struct Ingredient: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Verbatim printed line.
    public var rawText: String
    /// "For the dressing".
    public var section: String?
    /// nil = unquantified ("salt, to taste").
    public var quantity: Double?
    /// Ranges: "2–3" → quantity 2, quantityMax 3.
    public var quantityMax: Double?
    /// nil only when `quantity` is nil.
    public var unit: Unit?
    public var packageSize: PackageSize?
    /// "chopped tomatoes", "garlic", "eggs".
    public var name: String
    /// "finely chopped", "for frying".
    public var preparation: String?
    public var optional: Bool
    /// false for "for frying", "for greasing", "to serve".
    public var scalable: Bool
    public var confidence: Confidence

    public init(
        id: UUID = UUID(),
        rawText: String,
        section: String? = nil,
        quantity: Double? = nil,
        quantityMax: Double? = nil,
        unit: Unit? = nil,
        packageSize: PackageSize? = nil,
        name: String,
        preparation: String? = nil,
        optional: Bool = false,
        scalable: Bool = true,
        confidence: Confidence = .high
    ) {
        self.id = id
        self.rawText = rawText
        self.section = section
        self.quantity = quantity
        self.quantityMax = quantityMax
        self.unit = unit
        self.packageSize = packageSize
        self.name = name
        self.preparation = preparation
        self.optional = optional
        self.scalable = scalable
        self.confidence = confidence
    }

    public var isQuantified: Bool {
        quantity != nil
    }

    // `id` is assigned by the app, not the extractor, so it is optional on the way in (DECISIONS: Phase 0).
    private enum CodingKeys: String, CodingKey {
        case id, rawText, section, quantity, quantityMax, unit, packageSize, name, preparation, optional, scalable, confidence
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        rawText = try c.decode(String.self, forKey: .rawText)
        section = try c.decodeIfPresent(String.self, forKey: .section)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        quantityMax = try c.decodeIfPresent(Double.self, forKey: .quantityMax)
        unit = try c.decodeIfPresent(Unit.self, forKey: .unit)
        packageSize = try c.decodeIfPresent(PackageSize.self, forKey: .packageSize)
        name = try c.decode(String.self, forKey: .name)
        preparation = try c.decodeIfPresent(String.self, forKey: .preparation)
        optional = try c.decode(Bool.self, forKey: .optional)
        scalable = try c.decode(Bool.self, forKey: .scalable)
        confidence = try c.decode(Confidence.self, forKey: .confidence)
    }
}
