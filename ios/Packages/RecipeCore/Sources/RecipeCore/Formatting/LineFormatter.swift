import Foundation

/// SPEC §7 line text: `Name — amount unit (package)`, used for reminder titles and share text.
public enum LineFormatter {

    /// "Plain flour — 100 g", "Garlic — 4–6 cloves", "Eggs — ¾", "Salt", "Bay leaf — 1 (optional)".
    public static func lineText(for scaled: ScaledIngredient) -> String {
        var text = capitalised(scaled.source.name)
        if let amount = amountText(for: scaled) {
            text += " — " + amount
        }
        if scaled.source.optional {
            text += " (optional)"
        }
        return text
    }

    /// The part after the dash: "¼ tin (400 g)", "½–¾ tbsp", "¾". nil when the row is unquantified.
    public static func amountText(for scaled: ScaledIngredient) -> String? {
        guard let quantity = scaled.quantity else { return nil }
        let unit = scaled.unit ?? .each

        var text = NumberFormatting.amount(quantity, unit: unit)
        if let max = scaled.quantityMax {
            text += "–" + NumberFormatting.amount(max, unit: unit)
        }
        let word = unit.displayName(plural: (scaled.quantityMax ?? quantity) > 1)
        if !word.isEmpty {
            text += " " + word
        }
        if let packageSize = scaled.source.packageSize {
            text += " (" + packageSizeText(packageSize) + ")"
        }
        return text
    }

    /// "400 g", "1.5 kg" — shown as extracted; package sizes never scale.
    public static func packageSizeText(_ size: PackageSize) -> String {
        let number = NumberFormatting.amount(size.quantity, unit: size.unit)
        let word = size.unit.displayName(plural: size.quantity > 1)
        return word.isEmpty ? number : number + " " + word
    }

    /// Upper-cases the first character only: "plain flour" → "Plain flour", "Parmesan" stays.
    public static func capitalised(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }
}
