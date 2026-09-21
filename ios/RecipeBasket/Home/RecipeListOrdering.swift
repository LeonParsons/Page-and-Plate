import Foundation

/// Sort and group options for the Recipes list. Pure functions over `Recipe` so they can be tested without a view.
nonisolated enum RecipeListOrdering {

    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case newest, title, rating, lastExported

        var id: String { rawValue }

        var label: String {
            switch self {
            case .newest: "Newest first"
            case .title: "Title"
            case .rating: "Rating"
            case .lastExported: "Last added to Reminders"
            }
        }
    }

    enum Grouping: String, CaseIterable, Identifiable, Sendable {
        case none, book

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: "No grouping"
            case .book: "By book"
            }
        }
    }

    struct Group: Identifiable {
        /// Stable key: the lower-cased book name, "" for recipes without one.
        let id: String
        /// Display name (the first-seen spelling), nil for the no-book group.
        let name: String?
        let recipes: [Recipe]
    }

    @MainActor
    static func sort(_ recipes: [Recipe], by sort: Sort) -> [Recipe] {
        switch sort {
        case .newest:
            return recipes.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return recipes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:
            return recipes.sorted { a, b in
                switch (a.rating, b.rating) {
                case let (x?, y?) where x != y: return x > y
                case (.some, .none): return true
                case (.none, .some): return false
                default: return a.createdAt > b.createdAt
                }
            }
        case .lastExported:
            return recipes.sorted { a, b in
                switch (a.lastExportedAt, b.lastExportedAt) {
                case let (x?, y?): return x > y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.createdAt > b.createdAt
                }
            }
        }
    }

    @MainActor
    static func group(_ recipes: [Recipe], by grouping: Grouping, sort: Sort) -> [Group] {
        let sorted = self.sort(recipes, by: sort)
        switch grouping {
        case .none:
            return [Group(id: "", name: nil, recipes: sorted)]
        case .book:
            var order: [String] = []
            var names: [String: String] = [:]
            var members: [String: [Recipe]] = [:]
            for recipe in sorted {
                let name = recipe.book?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let key = name.lowercased()
                if members[key] == nil {
                    order.append(key)
                    names[key] = name
                    members[key] = []
                }
                members[key]!.append(recipe)
            }
            // Books alphabetically, the no-book group last; within a book, by page then the chosen sort.
            order.sort { a, b in
                if a.isEmpty != b.isEmpty { return b.isEmpty }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            return order.map { key in
                let inBook = members[key]!.sorted { a, b in
                    switch (a.page, b.page) {
                    case let (x?, y?) where x != y: return x < y
                    case (.some, .none): return true
                    case (.none, .some): return false
                    default: return false   // keep the incoming (sorted) order
                    }
                }
                return Group(id: key, name: key.isEmpty ? nil : names[key], recipes: inBook)
            }
        }
    }
}
