import Testing
@testable import RecipeCore

@Suite("LineFormatter and scaling (SPEC §7 line text)")
struct LineFormatterTests {

    private func line(_ name: String, _ qty: Double? = nil, _ unit: Unit? = nil,
                      max: Double? = nil, pkg: PackageSize? = nil, prep: String? = nil,
                      optional: Bool = false, scalable: Bool = true, factor: Double) -> String {
        Ingredient(rawText: name, section: "Section", quantity: qty, quantityMax: max, unit: unit, packageSize: pkg,
                   name: name, preparation: prep, optional: optional, scalable: scalable)
            .scaled(by: factor).lineText
    }

    @Test("Unit words pluralise above 1; abbreviations never do")
    func pluralisation() {
        #expect(line("tomatoes", 1, .tin, factor: 1) == "Tomatoes — 1 tin")
        #expect(line("tomatoes", 1, .tin, factor: 1.5) == "Tomatoes — 1½ tins")
        #expect(line("tomatoes", 1, .tin, factor: 0.25) == "Tomatoes — ¼ tin")
        #expect(line("basil", 1, .handful, factor: 2) == "Basil — 2 handfuls")
        #expect(line("nutmeg", 1, .pinch, factor: 2) == "Nutmeg — 2 pinches")
        #expect(line("parsley", 1, .bunch, factor: 2) == "Parsley — 2 bunches")
        #expect(line("bitters", 1, .dash, factor: 3) == "Bitters — 3 dashes")
        #expect(line("flour", 1, .cup, factor: 2) == "Flour — 2 cups")
        #expect(line("milk", 1, .pint, factor: 2) == "Milk — 2 pints")
        #expect(line("garlic", 2, .clove, max: 3, factor: 2) == "Garlic — 4–6 cloves")
        #expect(line("garlic", 1, .clove, max: 2, factor: 0.5) == "Garlic — ½–1 clove", "range max of 1 is not plural")

        #expect(line("flour", 250, .g, factor: 2) == "Flour — 500 g")
        #expect(line("oil", 1, .tbsp, factor: 2) == "Oil — 2 tbsp")
        #expect(line("salt", 1, .tsp, factor: 2) == "Salt — 2 tsp")
        #expect(line("potatoes", 1, .kg, factor: 2) == "Potatoes — 2 kg")
        #expect(line("beef", 1, .lb, factor: 2) == "Beef — 2 lb")
        #expect(line("cheese", 1.5, .oz, factor: 2) == "Cheese — 3 oz")
        #expect(line("cream", 1, .flOz, factor: 2) == "Cream — 2 fl oz")
        #expect(line("stock", 1, .l, factor: 2) == "Stock — 2 l")
        #expect(line("milk", 125, .ml, factor: 2) == "Milk — 250 ml")
    }

    @Test("`each` shows no unit word; a quantity with no unit is treated the same way")
    func each() {
        #expect(line("eggs", 3, .each, factor: 1) == "Eggs — 3")
        #expect(line("eggs", 2, .each, max: 3, factor: 1) == "Eggs — 2–3")
        #expect(line("eggs", 3, nil, factor: 1) == "Eggs — 3")
        #expect(line("eggs", 3, nil, factor: 0.25) == "Eggs — ¾")
    }

    @Test("Unquantified rows are the name only; optional adds a suffix either way")
    func unquantifiedAndOptional() {
        #expect(line("salt", factor: 3) == "Salt")
        #expect(line("salt", optional: true, factor: 3) == "Salt (optional)")
        #expect(line("bay leaf", 1, .each, optional: true, factor: 1) == "Bay leaf — 1 (optional)")
        #expect(line("chilli", 1, .each, optional: true, factor: 0.5) == "Chilli — ½ (optional)")
    }

    @Test("Preparation and section never appear")
    func preparationExcluded() {
        #expect(line("garlic", 2, .clove, prep: "crushed", factor: 1) == "Garlic — 2 cloves")
        #expect(line("oil", 2, .tbsp, prep: "for frying", scalable: false, factor: 5) == "Oil — 2 tbsp")
    }

    @Test("Package size is appended as extracted and never scales")
    func packageSize() {
        let tin = PackageSize(quantity: 400, unit: .g)
        #expect(line("tomatoes", 1, .tin, pkg: tin, factor: 0.25) == "Tomatoes — ¼ tin (400 g)")
        #expect(line("tomatoes", 1, .tin, pkg: tin, factor: 3) == "Tomatoes — 3 tins (400 g)")
        #expect(line("coconut milk", 1, .tin, pkg: PackageSize(quantity: 400, unit: .ml), factor: 1) == "Coconut milk — 1 tin (400 ml)")
        #expect(LineFormatter.packageSizeText(PackageSize(quantity: 1.5, unit: .kg)) == "1.5 kg")
        #expect(LineFormatter.packageSizeText(PackageSize(quantity: 0.5, unit: .l)) == "0.5 l")
    }

    @Test("Unscaled values display exactly as extracted: factor 1 and unscalable rows are never rounded")
    func unscaledPassThrough() {
        #expect(line("butter", 133.3, .g, factor: 1) == "Butter — 133.3 g")
        #expect(line("butter", 133.3, .g, scalable: false, factor: 3) == "Butter — 133.3 g")
        #expect(line("flour", 1.0 / 3, .cup, factor: 1) == "Flour — ⅓ cup")
        #expect(line("flour", 0.3, .cup, factor: 1) == "Flour — 0.3 cup")
        #expect(line("sugar", 1.75, .oz, factor: 1) == "Sugar — 1.75 oz")
        #expect(line("potatoes", 1200, .g, factor: 1) == "Potatoes — 1200 g", "promotion only applies to scaled values")
    }

    @Test("Ranges: display unit follows the upper value; equal ends collapse")
    func ranges() {
        #expect(line("cream", 2, .tbsp, max: 3, factor: 0.25) == "Cream — ½–¾ tbsp")
        #expect(line("flour", 900, .g, max: 1100, factor: 1.05) == "Flour — 0.95–1.16 kg")
        #expect(line("flour", 11, .g, max: 12, factor: 0.3) == "Flour — 3.5 g")
        #expect(line("chillies", 1, .each, max: 2, factor: 3) == "Chillies — 3–6")
    }

    @Test("Names are capitalised on the first character only")
    func capitalisation() {
        #expect(LineFormatter.capitalised("plain flour") == "Plain flour")
        #expect(LineFormatter.capitalised("Parmesan") == "Parmesan")
        #expect(LineFormatter.capitalised("éclair pastry") == "Éclair pastry")
        #expect(LineFormatter.capitalised("") == "")
        #expect(line("free-range eggs", 2, .each, factor: 1) == "Free-range eggs — 2")
    }

    @Test("amountText is nil when unquantified and otherwise the text after the dash")
    func amountText() {
        let salt = Ingredient(rawText: "salt", name: "salt").scaled(by: 2)
        #expect(LineFormatter.amountText(for: salt) == nil)
        let tin = Ingredient(rawText: "", quantity: 1, unit: .tin, packageSize: PackageSize(quantity: 400, unit: .g), name: "tomatoes").scaled(by: 0.25)
        #expect(LineFormatter.amountText(for: tin) == "¼ tin (400 g)")
        #expect(LineFormatter.lineText(for: tin) == tin.lineText)
    }

    @Test("ScaledIngredient bookkeeping")
    func scaledIngredient() {
        let flour = Ingredient(rawText: "200 g flour", quantity: 200, unit: .g, name: "flour")
        let doubled = flour.scaled(by: 2)
        #expect(doubled.isScaled)
        #expect(doubled.quantity == 400)
        #expect(doubled.unit == .g)
        #expect(doubled.factor == 2)
        #expect(doubled.source == flour)

        #expect(flour.scaled(by: 1).isScaled == false)
        #expect(Ingredient(rawText: "", quantity: 2, unit: .tbsp, name: "oil", scalable: false).scaled(by: 2).isScaled == false)
        #expect(Ingredient(rawText: "", name: "salt").scaled(by: 2).isScaled == false)

        let promoted = Ingredient(rawText: "", quantity: 750, unit: .g, name: "potatoes").scaled(by: 2)
        #expect(promoted.unit == .kg)
        #expect(promoted.quantity == 1.5)

        let all = [flour, Ingredient(rawText: "", name: "salt")].scaled(by: 2)
        #expect(all.map(\.source.name) == ["flour", "salt"])
    }
}
