import RecipeCore
import SwiftData
import SwiftUI

/// Recipes (home), SPEC §4: list on the left and the recipe on the right on iPad; a stack on iPhone.
struct HomeView: View {
    var remindersStore: any RemindersStoring = EventKitRemindersStore()

    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Environment(\.modelContext) private var modelContext
    @Environment(ExportSettings.self) private var settings
    @Environment(ScanQuota.self) private var quota
    @State private var selection: Recipe.ID?
    /// The sidebar holds the whole list *and* the Add/Sort/Group/Settings toolbar, so on iPad a collapsed
    /// sidebar leaves a screen with nothing on it and no way back. `.all` keeps it open; the user can still
    /// hide it with the toggle, and `.balanced` means it takes its own width rather than covering the recipe.
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isAdding = false
    @State private var isShowingSettings = false
    @AppStorage("list.sort") private var sortRaw = RecipeListOrdering.Sort.newest.rawValue
    @AppStorage("list.grouping") private var groupingRaw = RecipeListOrdering.Grouping.none.rawValue

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Scan a cookbook page to add your first recipe.")
                    } actions: {
                        Button("Add recipe") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.recipes) { recipe in
                                    RecipeListRow(recipe: recipe, showsBook: grouping == .none)
                                }
                                .onDelete { offsets in delete(offsets.map { group.recipes[$0] }) }
                            } header: {
                                if let name = group.name {
                                    Label(name, systemImage: "book.closed")
                                } else if grouping == .book {
                                    Text("No book")
                                }
                            }
                        }
                    }
                    .paperBackground()
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add recipe", systemImage: "plus") { isAdding = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Picker("Sort by", systemImage: "arrow.up.arrow.down", selection: $sortRaw) {
                        ForEach(RecipeListOrdering.Sort.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Picker("Group", systemImage: "rectangle.3.group", selection: $groupingRaw) {
                        ForEach(RecipeListOrdering.Grouping.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddRecipeView(lastBook: settings.lastBook, quota: quota)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(store: remindersStore)
            }
        } detail: {
            if let id = selection, let recipe = recipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe, remindersStore: remindersStore) { delete(recipe) }
            } else {
                ContentUnavailableView("Select a recipe", systemImage: "book", description: Text("Choose a recipe from the list, or add one."))
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sort: RecipeListOrdering.Sort {
        RecipeListOrdering.Sort(rawValue: sortRaw) ?? .newest
    }

    private var grouping: RecipeListOrdering.Grouping {
        RecipeListOrdering.Grouping(rawValue: groupingRaw) ?? .none
    }

    private var groups: [RecipeListOrdering.Group] {
        RecipeListOrdering.group(recipes, by: grouping, sort: sort)
    }

    private func delete(_ toDelete: [Recipe]) {
        for recipe in toDelete {
            delete(recipe)
        }
    }

    /// Clear the selection first so no view is still showing the recipe, then delete, then save on the next turn
    /// (saving synchronously detaches the pages while a row may still be rendering them).
    private func delete(_ recipe: Recipe) {
        if selection == recipe.id { selection = nil }
        modelContext.delete(recipe)
        Task { @MainActor in
            try? modelContext.save()
        }
    }
}

/// SPEC §4: thumbnail, title, rating if any, target portions and the last "added to Reminders" date if any.
/// Tapping the thumbnail opens the page photos; tapping anywhere else opens the recipe.
private struct RecipeListRow: View {
    let recipe: Recipe
    var showsBook = true
    @State private var isViewingPages = false

    var body: some View {
        HStack(spacing: 12) {
            if !recipe.isDeleted, let first = recipe.orderedPages.first, !first.isDeleted {
                Button { isViewingPages = true } label: {
                    PageThumbnail(data: first.imageData)
                        .frame(width: 56, height: 72)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page photo")
                .fullScreenCover(isPresented: $isViewingPages) {
                    PageViewerView(pages: recipe.isDeleted ? [] : recipe.orderedPages.map(\.imageData))
                }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 56, height: 72)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                if let rating = recipe.rating {
                    RatingStars(rating: rating)
                }
                Text(portionsLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let source = showsBook ? recipe.sourceText : recipe.page.map({ "p. \($0)" }) {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let exported = recipe.lastExportedAt {
                    Text("Added to Reminders \(exported.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var portionsLine: String {
        let unit = recipe.yield.unit
        let want = unit == "servings" ? "\(recipe.targetYield) \(recipe.targetYield == 1 ? "serving" : "servings")" : "\(recipe.targetYield) \(unit)"
        if let base = recipe.yield.quantity {
            let baseText = unit == "servings" ? "serves \(NumberFormatting.fraction(base))" : "makes \(NumberFormatting.fraction(base)) \(unit)"
            return "I want \(want) · \(baseText)"
        }
        return "I want \(want)"
    }
}

#Preview {
    HomeView(remindersStore: FakeRemindersStore(access: .fullAccess, lists: [.groceries, .shopping]))
        .environment(ExportSettings(defaults: UserDefaults(suiteName: "preview")!))
        .modelContainer(for: AppSchema.models, inMemory: true)
}
