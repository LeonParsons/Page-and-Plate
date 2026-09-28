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
    /// The share's own title. **Not shown anywhere** — see `Households.displayTitle(for:)`, which computes what
    /// a household is called. Kept because it is what CloudKit's sharing UI displays when an invite is sent, and
    /// because removing a stored property would stop every household already on a device from decoding.
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
///
/// `.mine` means "the plan that is mine to run" — which is the household you host once you host one, and your
/// personal week before that. Hosting **replaces** your own plan rather than sitting beside it (Leon,
/// 2026-09-26): a row you would never tap is worse than a rule to explain.
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
        static let hosted = "household.hosted"
        static let selection = "household.selection"
        static let endedNotice = "household.endedNotice"
        /// Phase 10 stored a single membership under these. Read once, then removed.
        static let legacyZoneName = "sharedPlan.zoneName"
        static let legacyOwnerName = "sharedPlan.ownerName"
        static let legacyOwnerTitle = "sharedPlan.ownerTitle"
    }

    private let defaults: UserDefaults
    private(set) var joined: [Household]
    /// The household this person runs, once they have created one. Their own week is projected into it and
    /// then belongs to it; before that there is no household and `current` is nil.
    private(set) var hosted: Household?
    private(set) var selection: PlanSelection
    /// A household that has gone, to tell this person about once.
    ///
    /// A revoked share reaches a member as a zone deletion and the rows simply disappear — so without this the
    /// household vanishes overnight with no explanation. **No reason is given**, because the reason is the
    /// owner's billing or their decision, and neither is ours to publish.
    private(set) var endedNotice: String?

    init(defaults: UserDefaults = .standard) {
        var joined = Self.load([Household].self, Key.households, from: defaults) ?? []
        if joined.isEmpty, let inherited = Self.adoptPhase10Membership(from: defaults) {
            joined = [inherited]
        }
        let hosted = Self.load(Household.self, Key.hosted, from: defaults)
        var selection = Self.load(PlanSelection.self, Key.selection, from: defaults) ?? .mine
        // A selection can outlive the household it names — the share was revoked while the app was closed.
        if case .household(let id) = selection, !joined.contains(where: { $0.id == id }) {
            selection = .mine
        }
        self.defaults = defaults
        self.joined = joined
        self.hosted = hosted
        self.selection = selection
        endedNotice = defaults.string(forKey: Key.endedNotice)
    }

    /// A household this person belonged to has stopped being shared.
    func recordEnded(_ household: Household, ownerName: String?) {
        endedNotice = ownerName.map { "\($0)'s plan is no longer shared." } ?? "A plan you were part of is no longer shared."
        defaults.set(endedNotice, forKey: Key.endedNotice)
    }

    func clearEndedNotice() {
        guard endedNotice != nil else { return }
        endedNotice = nil
        defaults.removeObject(forKey: Key.endedNotice)
    }

    /// The household on display, or nil when this person has no household at all and is looking at their own
    /// personal week. `.mine` resolves to the household they host, which is what makes hosting *replace*
    /// their own plan rather than sit beside it.
    var current: Household? {
        switch selection {
        case .mine: hosted
        case .household(let id): joined.first { $0.id == id }
        }
    }

    var isShowingHousehold: Bool { current != nil }

    /// The plan that is yours to run — whether or not you have shared it. **Always this**, because you only
    /// ever own one.
    static let myPlanTitle = "My plan"

    /// The first household you joined. Somebody else's plan, which you are part of.
    static let ourPlanTitle = "Our plan"

    /// What the "My plan" row reads.
    var mineTitle: String { Self.myPlanTitle }

    /// The households this person joined, in the order they joined them. What `displayTitle` numbers by, so it
    /// has to be stable across launches — hence `joinedAt`, with the id to break a tie.
    var orderedJoined: [Household] {
        joined.sorted { ($0.joinedAt, $0.id) < ($1.joinedAt, $1.id) }
    }

    /// Every household this person is in, the one they host first.
    var ordered: [Household] {
        (hosted.map { [$0] } ?? []) + orderedJoined
    }

    /// What to call a household on screen — **never the name its owner gave it** (Leon, 2026-09-28).
    ///
    /// A plan's title shares the navigation bar with the week, and any name long enough to be meaningful is too
    /// long to sit beside "This week": "The Parsons · This week" truncated, and so would every real household
    /// name. So a household is not named at all. Yours is "My plan", the first you joined is "Our plan", and any
    /// after that are numbered. **Who it belongs to is what tells them apart**, shown under the row in Settings,
    /// and that is a better answer than a name anyway — a member could never rename somebody else's household,
    /// so a name they found confusing was one they were stuck with.
    ///
    /// The consequence, accepted: leaving a household renumbers the ones after it. The owner's name under the
    /// row is what a person actually recognises, and it does not move.
    func displayTitle(for household: Household) -> String {
        if hosted?.id == household.id { return Self.myPlanTitle }
        guard let index = orderedJoined.firstIndex(where: { $0.id == household.id }) else {
            return Self.ourPlanTitle
        }
        return index == 0 ? Self.ourPlanTitle : "Plan \(index + 1)"
    }

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

    /// Creating your own household, or re-reading the share on a later launch in case it was renamed.
    ///
    /// Recording it does not change what is on display: `.mine` was already the selection, and it now
    /// resolves to this household. That is deliberate — the owner's week is seeded from their personal week,
    /// so the screen looks the same the moment before and the moment after.
    func host(zoneID: CKRecordZone.ID, title: String) {
        if var existing = hosted, existing.id == Household(zoneID: zoneID, title: title).id {
            existing.title = title
            hosted = existing
        } else {
            hosted = Household(zoneID: zoneID, title: title)
        }
        persist()
    }

    func host(_ share: CKShare) {
        host(zoneID: share.recordID.zoneID, title: Self.title(for: share))
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

    /// Signing out of iCloud, and nothing else.
    ///
    /// **Stopping sharing does not call this.** Removing the participants leaves the zone, the week and the
    /// name alone, so the household simply has one member — lossless, and re-sharing picks it straight back
    /// up. Leon accepted (2026-09-26) that there is therefore no way back to the personal week while a
    /// household exists; giving the owner the equivalent of Leave is 11c's job.
    func stopHosting() {
        hosted = nil
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
        if let hosted {
            defaults.set(try? JSONEncoder().encode(hosted), forKey: Key.hosted)
        } else {
            defaults.removeObject(forKey: Key.hosted)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
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
