import EventKit
import Foundation
import RecipeCore

/// A Reminders list (an `EKCalendar` of the reminder entity type).
nonisolated struct ReminderList: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    /// "iCloud", "On My iPhone", …
    let sourceTitle: String
    let allowsModifications: Bool
}

nonisolated enum RemindersAccess: Equatable, Sendable {
    case notDetermined, fullAccess, writeOnly, denied, restricted
}

nonisolated enum RemindersError: Error, Equatable {
    case accessDenied
    case listNotFound
    case listReadOnly
    case saveFailed(String)

    var message: String {
        switch self {
        case .accessDenied: "Reminders access is off for \(Brand.name)."
        case .listNotFound: "That Reminders list no longer exists. Choose another one."
        case .listReadOnly: "That list can't be changed. Choose another one."
        case let .saveFailed(detail): "Couldn't add the reminders: \(detail)"
        }
    }
}

/// One reminder to add: the title and the notes. All the store ever needs to know about a row.
nonisolated struct ReminderItem: Equatable, Hashable, Sendable {
    let title: String
    let notes: String
}

/// Everything the export needs from Reminders. Adds only — never reads back, updates or deletes reminders
/// (CLAUDE.md rule 9).
nonisolated protocol RemindersStoring: Sendable {
    func authorizationStatus() -> RemindersAccess
    func requestAccess() async -> RemindersAccess
    func lists() -> [ReminderList]
    func defaultList() -> ReminderList?
    /// Returns an existing list called "Shopping" in the default source, or creates one there.
    func createShoppingList() throws -> ReminderList
    /// One reminder per item, saved in one commit. Returns the number added.
    func add(_ items: [ReminderItem], to listID: String) throws -> Int
}

/// The real thing, over one `EKEventStore`.
nonisolated final class EventKitRemindersStore: RemindersStoring, @unchecked Sendable {
    static let shoppingListTitle = "Shopping"
    private let store = EKEventStore()

    func authorizationStatus() -> RemindersAccess {
        Self.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    func requestAccess() async -> RemindersAccess {
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            // The status below reports whatever the user chose.
        }
        return authorizationStatus()
    }

    func lists() -> [ReminderList] {
        store.calendars(for: .reminder)
            .map(Self.list(from:))
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    func defaultList() -> ReminderList? {
        store.defaultCalendarForNewReminders().map(Self.list(from:))
    }

    func createShoppingList() throws -> ReminderList {
        let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first
        guard let source else { throw RemindersError.saveFailed("No Reminders account is available.") }

        if let existing = source.calendars(for: .reminder).first(where: { $0.title == Self.shoppingListTitle }) {
            return Self.list(from: existing)
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = Self.shoppingListTitle
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw RemindersError.saveFailed(error.localizedDescription)
        }
        return Self.list(from: calendar)
    }

    func add(_ items: [ReminderItem], to listID: String) throws -> Int {
        guard let calendar = store.calendar(withIdentifier: listID) else { throw RemindersError.listNotFound }
        guard calendar.allowsContentModifications else { throw RemindersError.listReadOnly }
        do {
            for item in items {
                let reminder = EKReminder(eventStore: store)
                reminder.title = item.title
                reminder.notes = item.notes
                reminder.calendar = calendar
                try store.save(reminder, commit: false)
            }
            try store.commit()
        } catch {
            store.reset()
            throw RemindersError.saveFailed(error.localizedDescription)
        }
        return items.count
    }

    private static func map(_ status: EKAuthorizationStatus) -> RemindersAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    private static func list(from calendar: EKCalendar) -> ReminderList {
        ReminderList(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            sourceTitle: calendar.source?.title ?? "",
            allowsModifications: calendar.allowsContentModifications
        )
    }
}

/// For tests and previews: an in-memory Reminders that records what was added.
extension ReminderList {
    /// Sample lists for tests and previews.
    static let groceries = ReminderList(id: "groceries", title: "Groceries", sourceTitle: "iCloud", allowsModifications: true)
    static let shopping = ReminderList(id: "shopping", title: "Shopping", sourceTitle: "iCloud", allowsModifications: true)
}

final class FakeRemindersStore: RemindersStoring, @unchecked Sendable {

    struct Added: Equatable {
        let item: ReminderItem
        let listID: String
    }

    private(set) var access: RemindersAccess
    private(set) var storedLists: [ReminderList]
    private let defaultListID: String?
    private let grantOnRequest: RemindersAccess
    private(set) var added: [Added] = []
    private(set) var requestCount = 0
    var failNextAdd: RemindersError?

    init(access: RemindersAccess, lists: [ReminderList], defaultListID: String? = nil, grantOnRequest: RemindersAccess = .fullAccess) {
        self.access = access
        self.storedLists = lists
        self.defaultListID = defaultListID ?? lists.first?.id
        self.grantOnRequest = grantOnRequest
    }

    func authorizationStatus() -> RemindersAccess { access }

    func requestAccess() async -> RemindersAccess {
        requestCount += 1
        if access == .notDetermined { access = grantOnRequest }
        return access
    }

    func lists() -> [ReminderList] { storedLists }

    func defaultList() -> ReminderList? {
        storedLists.first { $0.id == defaultListID } ?? storedLists.first
    }

    func createShoppingList() throws -> ReminderList {
        if let existing = storedLists.first(where: { $0.title == EventKitRemindersStore.shoppingListTitle }) { return existing }
        let list = ReminderList(id: "shopping-\(storedLists.count)", title: EventKitRemindersStore.shoppingListTitle, sourceTitle: "iCloud", allowsModifications: true)
        storedLists.append(list)
        return list
    }

    func add(_ items: [ReminderItem], to listID: String) throws -> Int {
        if let error = failNextAdd {
            failNextAdd = nil
            throw error
        }
        guard storedLists.contains(where: { $0.id == listID }) else { throw RemindersError.listNotFound }
        added.append(contentsOf: items.map { Added(item: $0, listID: listID) })
        return items.count
    }
}
