import RecipeCore

/// Rows grouped under one sub-heading ("For the curry paste"); `name == nil` is the main list.
nonisolated struct IngredientSection<Row: Equatable & Sendable>: Equatable, Sendable {
    var name: String?
    var rows: [Row]
}

extension Array where Element: Equatable & Sendable {
    /// Groups in order of first appearance, with the unsectioned rows first (SPEC §4 "grouped by section").
    nonisolated func sectioned(by key: (Element) -> String?) -> [IngredientSection<Element>] {
        var order: [String?] = []
        var grouped: [String?: [Element]] = [:]
        for element in self {
            let section = key(element)
            if grouped[section] == nil {
                order.append(section)
                grouped[section] = []
            }
            grouped[section]!.append(element)
        }
        order.sort { a, b in a == nil && b != nil }
        return order.map { IngredientSection(name: $0, rows: grouped[$0] ?? []) }
    }
}

extension Array where Element == Ingredient {
    nonisolated var sectioned: [IngredientSection<Ingredient>] {
        sectioned { $0.section }
    }
}

extension Array where Element == ScaledIngredient {
    nonisolated var sectioned: [IngredientSection<ScaledIngredient>] {
        sectioned { $0.source.section }
    }
}
