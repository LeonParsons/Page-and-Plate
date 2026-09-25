import CloudKit
import Foundation

/// A household plan this person belongs to: someone else's plan they have accepted an invite to.
///
/// The `title` is what the owner named it when they shared, carried on the `CKShare`. Phase 10 derived a
/// name from the owner's iCloud identity instead, which produced "Shared's plan" when CloudKit would not
/// say who the owner was — a name the owner chose cannot fail that way.
struct Household: Codable, Hashable, Identifiable, Sendable {
    let zoneName: String
    let ownerName: String
    var title: String
    var joinedAt: Date

    /// Stable across launches and unique per zone, which is what `PlanSelection` stores.
    var id: String { "\(zoneName)|\(ownerName)" }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    init(zoneID: CKRecordZone.ID, title: String, joinedAt: Date = .now) {
        self.zoneName = zoneID.zoneName
        self.ownerName = zoneID.ownerName
        self.title = title
        self.joinedAt = joinedAt
    }
}

/// Which plan is on display. Exactly one, always (SPEC §10, reshaped 2026-09-25).
enum PlanSelection: Codable, Hashable, Sendable {
    case mine
    case household(String)
}

/// The households this person belongs to, and which plan they are looking at.
///
/// **One plan on display, ever.** Phase 10 gave the guest a switcher on the Plan tab and left their own
/// plan alongside the owner's; using it showed that a person wants one week, not a toggle. Joining a
/// household hides your own plan — *hides*, never deletes: your library keeps mirroring to your own private
/// zone throughout, and leaving brings the week back untouched.
///
/// Hosting and joining are independent. If you host a household and then join someone else's, your own
/// household keeps running for the people in it; you are simply looking at theirs.
@Observable
@MainActor
final class Households {
    /// The scene delegate is created by UIKit and cannot be handed dependencies, so it reaches the app
    /// through this. The only shared instance in the app, and only because UIKit leaves no other seam.
    static let shared = Households()

    private enum Key {
        static let households = "household.joined"
        static let selection = "household.selection"
        /// Phase 10 stored a single membership under these. Read once, then removed.
        static let legacyZoneName = "sharedPlan.zoneName"
        static let legacyOwnerName = "sharedPlan.ownerName"
        static let legacyOwnerTitle = "sharedPlan.ownerTitle"
    }

    private let defaults: UserDefaults
    private(set) var joined: [Household]
    private(set) var selection: PlanSelection

    init(defaults: UserDefaults = .standard) {
        var joined = Self.load(from: defaults) ?? []
        if joined.isEmpty, let inherited = Self.adoptPhase10Membership(from: defaults) {
            joined = [inherited]
        }
        var selection = Self.loadSelection(from: defaults)
        // A selection can outlive the household it names — the share was revoked while the app was closed.
        if case .household(let id) = selection, !joined.contains(where: { $0.id == id }) {
            selection = .mine
        }
        self.defaults = defaults
        self.joined = joined
        self.selection = selection
    }

    /// The household on display, or nil when it is the person's own plan.
    var current: Household? {
        guard case .household(let id) = selection else { return nil }
        return joined.first { $0.id == id }
    }

    var isShowingHousehold: Bool { current != nil }

    /// Accepting an invite. Re-accepting one already joined updates its name rather than adding it twice.
    func join(zoneID: CKRecordZone.ID, title: String) {
        let household = Household(zoneID: zoneID, title: title)
        if let index = joined.firstIndex(where: { $0.id == household.id }) {
            joined[index].title = title
        } else {
            joined.append(household)
        }
        // Accepting an invite is an act of intent: show it.
        selection = .household(household.id)
        persist()
    }

    func join(_ share: CKShare) {
        join(zoneID: share.recordID.zoneID, title: Self.title(for: share))
    }

    /// Leaving, or being removed. Only this household goes; the person's own plan is never touched.
    func leave(_ household: Household) {
        leave(id: household.id)
    }

    func leave(id: String) {
        joined.removeAll { $0.id == id }
        if case .household(let shown) = selection, shown == id {
            selection = .mine
        }
        persist()
    }

    func select(_ selection: PlanSelection) {
        if case .household(let id) = selection, !joined.contains(where: { $0.id == id }) { return }
        self.selection = selection
        persist()
    }

    // MARK: Private

    private func persist() {
        defaults.set(try? JSONEncoder().encode(joined), forKey: Key.households)
        defaults.set(try? JSONEncoder().encode(selection), forKey: Key.selection)
    }

    private static func load(from defaults: UserDefaults) -> [Household]? {
        guard let data = defaults.data(forKey: Key.households) else { return nil }
        return try? JSONDecoder().decode([Household].self, from: data)
    }

    private static func loadSelection(from defaults: UserDefaults) -> PlanSelection {
        guard let data = defaults.data(forKey: Key.selection),
              let selection = try? JSONDecoder().decode(PlanSelection.self, from: data)
        else { return .mine }
        return selection
    }

    /// Phase 10's single membership becomes the first household, so nobody who had accepted an invite has
    /// to accept it again. Leon's iPhone, the iPad and Sara's phone all carry these keys.
    private static func adoptPhase10Membership(from defaults: UserDefaults) -> Household? {
        guard let zoneName = defaults.string(forKey: Key.legacyZoneName),
              let ownerName = defaults.string(forKey: Key.legacyOwnerName)
        else { return nil }

        // Phase 10 had no household name, only the owner's given name if CloudKit would say. Neither makes
        // a good title, so the household is named for what it is until the owner shares again.
        let title = defaults.string(forKey: Key.legacyOwnerTitle).map { "\($0)'s plan" } ?? "Shared plan"
        for key in [Key.legacyZoneName, Key.legacyOwnerName, Key.legacyOwnerTitle] {
            defaults.removeObject(forKey: key)
        }
        return Household(zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName), title: title)
    }

    /// The name the owner gave the household. `UICloudSharingController` writes it to the share's title, so
    /// it is there for every participant; the fallback is only for a share made before naming existed.
    private static func title(for share: CKShare) -> String {
        (share[CKShare.SystemFieldKey.title] as? String) ?? "Shared plan"
    }
}
