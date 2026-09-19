import Testing
@testable import RecipeCore

@Suite("Staples (SPEC §5)")
struct StaplesTests {

    @Test("Default staples are the five from the spec")
    func defaults() {
        #expect(Staples.defaultNames == ["salt", "black pepper", "olive oil", "vegetable oil", "water"])
    }

    @Test("Matching is case-insensitive, trimmed and exact", arguments: [
        ("salt", true), ("Salt", true), ("  BLACK PEPPER ", true), ("olive oil", true),
        ("sea salt", false), ("salted butter", false), ("pepper", false), ("", false),
    ])
    func matching(name: String, expected: Bool) {
        #expect(Staples.isStaple(name) == expected)
    }

    @Test("A custom list replaces the defaults")
    func customList() {
        #expect(Staples.isStaple("sea salt", in: ["Sea Salt"]) == true)
        #expect(Staples.isStaple("salt", in: ["Sea Salt"]) == false)
    }
}
