import RecipeCore
import SwiftData
import SwiftUI

/// "Add to plan…" from a recipe: pick a day in this week or next. Shows what each day already has.
struct DayPickerSheet: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var meals: [PlannedMeal]
    @State private var errorMessage: String?
    private let weeks: [PlanWeek]

    /// - Parameter calendar: the cook's own week, so "this week and next" here means the same seven days the
    ///   Plan tab is showing. A `@Query` predicate is fixed at init, so this cannot be read from the
    ///   environment and the caller passes it in.
    init(recipe: Recipe, calendar: Calendar = .current) {
        self.recipe = recipe
        let thisWeek = PlanWeek(containing: PlanDay(.now), calendar: calendar)
        weeks = [thisWeek, thisWeek.next()]
        let start = thisWeek.start.isoString
        let end = thisWeek.next().end.isoString
        _meals = Query(
            filter: #Predicate<PlannedMeal> { $0.dayKey >= start && $0.dayKey <= end },
            sort: [SortDescriptor(\PlannedMeal.dayKey), SortDescriptor(\PlannedMeal.order)]
        )
    }

    private var byDay: [PlanDay: [PlannedMeal]] {
        PlanOrdering.byDay(meals.filter { !$0.isDeleted })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(weeks, id: \.start) { week in
                    Section(week.title) {
                        ForEach(week.days) { day in
                            Button { add(day) } label: {
                                DayRow(day: day, planned: byDay[day] ?? [], recipe: recipe)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Add to plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't add to the plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func add(_ day: PlanDay) {
        do {
            try PlanEditor(context: modelContext).add(recipe, to: day)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct DayRow: View {
        let day: PlanDay
        let planned: [PlannedMeal]
        let recipe: Recipe

        private var alreadyHere: Bool {
            planned.contains { $0.recipe?.id == recipe.id }
        }

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(day.longText)
                            .foregroundStyle(day.isToday ? Color.accentColor : .primary)
                        if day.isToday {
                            Text("Today")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if !planned.isEmpty {
                        Text(planned.compactMap { $0.recipe?.title }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: alreadyHere ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(alreadyHere ? Color.green : Color.accentColor)
                    .font(.title3)
                    .accessibilityLabel(alreadyHere ? "Already planned, add again" : "Add")
            }
            .contentShape(Rectangle())
        }
    }
}
