import RecipeCore
import SwiftData
import SwiftUI

/// The Plan tab: one week at a time, any number of meals per day (SPEC §4 Plan).
struct PlannerView: View {
    /// Whose week the Plan tab is showing. A guest has their own plan *and* the one shared with them; theirs
    /// is never displaced (SPEC §10).
    enum Scope: Hashable {
        case mine
        case shared
    }

    var remindersStore: any RemindersStoring = EventKitRemindersStore()
    var guestPlan: SharedPlanContext?

    @Environment(\.modelContext) private var modelContext
    @Environment(ExportSettings.self) private var exportSettings
    /// Every planned meal: a `@Query` predicate is fixed at init, and recreating the view per week made the
    /// navigation title vanish and reappear on each ‹ › tap. A few rows per week, never many.
    @Query(sort: [SortDescriptor(\PlannedMeal.dayKey), SortDescriptor(\PlannedMeal.order)]) private var allMeals: [PlannedMeal]
    @State private var week = PlanWeek(containing: PlanDay(.now))
    @State private var addingTo: PlanDay?
    @State private var isShopping = false
    @State private var isShowingSettings = false
    @State private var isConfirmingClear = false
    @State private var scope: Scope = .mine

    private var isGuest: Bool {
        guestPlan?.membership.isGuest ?? false
    }

    /// "This week" on your own plan; "Leon · This week" on someone else's, so it is never ambiguous whose
    /// meals you are looking at. CloudKit often won't name the owner, hence the fallback.
    private var navigationTitle: String {
        guard scope == .shared else { return week.title }
        return "\(guestPlan?.membership.ownerTitle ?? "Shared") · \(week.title)"
    }

    /// "Leon's week", or just "Shared week" when CloudKit won't say who they are.
    private var sharedWeekLabel: String {
        guestPlan?.membership.ownerTitle.map { "\($0)'s week" } ?? "Shared week"
    }

    private var weekMeals: [PlannedMeal] {
        allMeals.filter { !$0.isDeleted && week.contains($0.day) }
    }

    /// What Shop exports: the week's meals whose recipe is still here.
    private var shoppable: [PlannedMeal] {
        weekMeals.filter { $0.recipe.map { !$0.isDeleted } ?? false }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // A guest gets a visible switcher, not a menu hidden behind the title: the first person to
                // accept an invite could not find `toolbarTitleMenu` at all, and there is no affordance on a
                // large title to tell them it is there.
                if isGuest {
                    Picker("Whose week", selection: $scope) {
                        Text("My week").tag(Scope.mine)
                        Text(sharedWeekLabel).tag(Scope.shared)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                Group {
                    if scope == .shared, let guestPlan {
                        SharedWeekView(week: week, client: guestPlan.client, remindersStore: remindersStore)
                            .modelContainer(guestPlan.container)
                    } else {
                        WeekView(week: week, meals: weekMeals, remindersStore: remindersStore, onAdd: { addingTo = $0 }, onDeleteRecipe: deleteRecipe)
                    }
                }
            }
                .navigationTitle(navigationTitle)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("Previous week", systemImage: "chevron.left") { week = week.previous() }
                        Button("Next week", systemImage: "chevron.right") { week = week.next() }
                        if !week.contains(PlanDay(.now)) {
                            Button("Today") { week = PlanWeek(containing: PlanDay(.now)) }
                        }
                    }
                    if scope == .mine {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Shop", systemImage: "cart") { isShopping = true }
                                .disabled(shoppable.isEmpty)
                        }
                    }
                    if scope == .mine {
                        ToolbarItem(placement: .secondaryAction) {
                            Button("Clear week…", systemImage: "calendar.badge.minus", role: .destructive) { isConfirmingClear = true }
                        }
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    }
                }
                .sheet(item: $addingTo) { day in
                    AddMealSheet(day: day)
                }
                .sheet(isPresented: $isShopping) {
                    ExportSheet(week: week, meals: shoppable, store: remindersStore, settings: exportSettings)
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView(store: remindersStore)
                }
                .confirmationDialog("Clear \(week.title.lowercased())?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                    Button("Clear \(week.rangeText)", role: .destructive) { try? PlanEditor(context: modelContext).clear(week) }
                } message: {
                    Text("Removes every meal from this week's plan. The recipes stay in your library.")
                }
        }
    }

    /// Deleting a recipe from a detail screen reached through the plan, by the same rule as Recipes.
    private func deleteRecipe(_ recipe: Recipe) {
        RecipeDeletion.delete(recipe, from: modelContext)
    }
}

extension PlanDay: @retroactive Identifiable {
    public var id: String { isoString }
}

/// One week as a list of days, over the week's meals in day-then-order.
struct WeekView: View {
    let week: PlanWeek
    let meals: [PlannedMeal]
    let remindersStore: any RemindersStoring
    let onAdd: (PlanDay) -> Void
    let onDeleteRecipe: (Recipe) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var movingMeal: PlannedMeal?

    private var editor: PlanEditor {
        PlanEditor(context: modelContext)
    }

    private var byDay: [PlanDay: [PlannedMeal]] {
        PlanOrdering.byDay(meals)
    }

    var body: some View {
        List {
            ForEach(week.days) { day in
                let dayMeals = byDay[day] ?? []
                Section {
                    if dayMeals.isEmpty {
                        Text("Nothing planned")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(dayMeals) { meal in
                        if let recipe = meal.recipe, !recipe.isDeleted {
                            NavigationLink {
                                RecipeDetailView(recipe: recipe, meal: meal, remindersStore: remindersStore) { onDeleteRecipe(recipe) }
                            } label: {
                                PlannedMealRow(data: MealRowData(meal: meal, recipe: recipe)) { editor.setPortions(meal, $0) }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Remove", systemImage: "trash", role: .destructive) { try? editor.remove(meal) }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Move", systemImage: "arrow.turn.down.right") { movingMeal = meal }
                                    .tint(.indigo)
                            }
                            .contextMenu {
                                Menu("Move to", systemImage: "arrow.turn.down.right") {
                                    ForEach(week.days.filter { $0 != day }) { target in
                                        Button(target.longText) { try? editor.move(meal, to: target) }
                                    }
                                }
                                Button("Remove from plan", systemImage: "trash", role: .destructive) { try? editor.remove(meal) }
                            }
                        }
                    }
                    .onMove { source, destination in try? editor.reorder(on: day, from: source, to: destination) }
                    Button { onAdd(day) } label: {
                        Label("Add meal", systemImage: "plus.circle")
                    }
                } header: {
                    DayHeader(day: day)
                }
            }
        }
        .paperBackground()
        .confirmationDialog("Move to", isPresented: Binding(get: { movingMeal != nil }, set: { if !$0 { movingMeal = nil } }), titleVisibility: .visible) {
            if let meal = movingMeal {
                ForEach(week.days.filter { $0 != meal.day }) { target in
                    Button(target.longText) { try? editor.move(meal, to: target) }
                }
            }
        }
    }
}

private struct DayHeader: View {
    let day: PlanDay

    var body: some View {
        HStack(spacing: 6) {
            if day.isToday {
                Text("Today")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .textCase(nil)
            }
            Text(day.longText)
                .foregroundStyle(day.isToday ? Color.accentColor : .secondary)
        }
    }
}

/// Everything a meal row draws, as plain values — so the owner's week and a guest's shared week render
/// identically, including the accessibility-size layout, without the row knowing which store it came from.
struct MealRowData: Equatable {
    var title: String
    var thumbnail: Data?
    var rating: Int?
    var sourceText: String?
    var portions: Int
    var yieldUnit: String
    /// The owner's "added to Reminders" tick. Always false on a shared week: the export stays personal.
    var isExported: Bool = false

    @MainActor
    init(meal: PlannedMeal, recipe: Recipe) {
        let page = recipe.orderedPages.first
        self.init(
            title: recipe.title,
            thumbnail: (page?.isDeleted == false) ? page?.imageData : nil,
            rating: recipe.rating,
            sourceText: recipe.sourceText,
            portions: meal.portions,
            yieldUnit: recipe.yield.unit,
            isExported: meal.exportedAt != nil
        )
    }

    init(title: String, thumbnail: Data?, rating: Int?, sourceText: String?, portions: Int, yieldUnit: String, isExported: Bool = false) {
        self.title = title
        self.thumbnail = thumbnail
        self.rating = rating
        self.sourceText = sourceText
        self.portions = portions
        self.yieldUnit = yieldUnit
        self.isExported = isExported
    }
}

/// Thumbnail, title, rating if any, the meal's own portions (with a stepper), and where the recipe lives.
struct PlannedMealRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let data: MealRowData
    let onPortions: (Int) -> Void

    var body: some View {
        if typeSize.isAccessibilitySize {
            // Side by side, the portions and the stepper cannot shrink, so they crush the title to a few
            // letters. At these sizes the row becomes two rows instead.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail
                    details
                }
                HStack(spacing: 12) {
                    portions
                    Spacer(minLength: 4)
                    stepper
                }
            }
        } else {
            HStack(spacing: 12) {
                thumbnail
                details
                Spacer(minLength: 4)
                // The portions sit above the stepper rather than in the left column: they read as one
                // control, and it takes a line out of the tallest column, so every row is shorter.
                VStack(alignment: .trailing, spacing: 4) {
                    portions
                    stepper
                }
                .fixedSize()
            }
        }
    }

    /// Decorative: the title beside it says what the meal is, and a photo of a cookbook page has nothing
    /// useful to announce.
    @ViewBuilder private var thumbnail: some View {
        Group {
            if let image = data.thumbnail {
                PageThumbnail(data: image)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
            }
        }
        .frame(width: 44, height: 56)
        .accessibilityHidden(true)
    }

    /// Combined, so it reads as "Chickpea arrabbiata, rated 4 of 5, LEON Happy Curries, p. 110" rather than
    /// three separate stops.
    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(data.title)
                .font(.headline)
                .lineLimit(2)
            if let rating = data.rating {
                RatingStars(rating: rating)
            }
            if let source = data.sourceText {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var portions: some View {
        HStack(spacing: 4) {
            Text("for \(ShoppingExport.portionsText(targetYield: data.portions, yieldUnit: data.yieldUnit))")
                .lineLimit(1)
            if data.isExported {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Added to Reminders")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var stepper: some View {
        Stepper("Portions", value: Binding(get: { data.portions }, set: { onPortions($0) }), in: Portions.range)
            .labelsHidden()
    }
}
