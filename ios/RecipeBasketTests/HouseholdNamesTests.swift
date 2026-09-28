import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RecipeBasket

/// Saying who is in a household.
///
/// **CloudKit will not.** `CKUserIdentity.nameComponents` needs the user-discoverability permission, and iOS 17
/// removed that permission and every `discoverUserIdentity` API — the SDK header says "No longer supported". So
/// a share participant's name is nil on every build this app can ship, and reading the share can never produce
/// one. Each person types their own and publishes it beside their recipes; these are what that has to do.
@Suite("Who is in the household")
@MainActor
struct HouseholdNamesTests {

    private let parsons = Household(
        zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_sara"),
        title: "ignored"
    )

    private let container: ModelContainer

    init() throws {
        container = try SharedStore.make(inMemory: true)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.names.\(UUID().uuidString)")!
    }

    // MARK: The record

    @Test("A member record is filed under the author's id, not a UUID, and carries their name")
    func aMemberRecordIsBuiltFromTheRow() throws {
        let context = container.mainContext
        let inbox = HouseholdInbox(context: context)
        try inbox.upsert(member: "_sara", name: "Sara Parsons", isOwner: true, in: parsons)

        let records = HouseholdRecords(context: context)
        let id = CKRecord.ID(recordName: "_sara", zoneID: parsons.zoneID)
        let record = try #require(records.record(for: id, in: parsons))

        #expect(record.recordType == SharedWeekZone.RecordType.member)
        #expect(record[SharedWeekZone.MemberKey.displayName] as? String == "Sara Parsons")
    }

    @Test("Renaming yourself is an update, so it carries the metadata the last save returned")
    func renamingIsAnUpdate() throws {
        let context = container.mainContext
        let inbox = HouseholdInbox(context: context)
        let records = HouseholdRecords(context: context)
        try inbox.upsert(member: "_sara", name: "Sara", isOwner: true, in: parsons)
        let id = CKRecord.ID(recordName: "_sara", zoneID: parsons.zoneID)

        // Stand-in for the change tag, which only a server sets: a zone the app would never ask for itself.
        records.remember(
            CKRecord(
                recordType: SharedWeekZone.RecordType.member,
                recordID: CKRecord.ID(
                    recordName: "_sara",
                    zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_server")
                )
            ),
            in: parsons
        )
        try inbox.upsert(member: "_sara", name: "Sara Parsons", isOwner: true, in: parsons)

        let record = try #require(records.record(for: id, in: parsons))
        // Built on what the server gave us — without this a rename is a tagless save and CloudKit refuses it,
        // so a name could be set once and never corrected.
        #expect(record.recordID.zoneID.ownerName == "_server")
        #expect(record[SharedWeekZone.MemberKey.displayName] as? String == "Sara Parsons")
    }

    @Test("An arriving member record names that person everywhere they appear")
    func anArrivingRecordIsCached() throws {
        let context = container.mainContext
        let record = CKRecord(
            recordType: SharedWeekZone.RecordType.member,
            recordID: CKRecord.ID(recordName: "_sara", zoneID: parsons.zoneID)
        )
        record[SharedWeekZone.MemberKey.displayName] = "Sara Parsons"

        HouseholdInbox(context: context).apply(record, in: parsons)

        #expect(try HouseholdInbox(context: context).member(authorID: "_sara", in: parsons)?.displayName == "Sara Parsons")
        // One person has one name, whichever household you meet them in.
        #expect(HouseholdMembers.shared.name(for: "_sara") == "Sara Parsons")
    }

    @Test("Leaving a household takes its member rows with everything else")
    func leavingTakesTheMembers() throws {
        let context = container.mainContext
        let other = Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"),
            title: "ignored"
        )
        let inbox = HouseholdInbox(context: context)
        try inbox.upsert(member: "_sara", name: "Sara", isOwner: true, in: parsons)
        try inbox.upsert(member: "_grandma", name: "Nan", isOwner: true, in: other)

        try SharedStore.empty(context, household: parsons.id)

        #expect(try inbox.member(authorID: "_sara", in: parsons) == nil)
        #expect(try inbox.member(authorID: "_grandma", in: other) != nil)
    }

    // MARK: What the screen reads

    @Test("The owner is whoever said so on their own record — no ids are compared")
    func theOwnerIsNamedFromTheirOwnFlag() throws {
        let context = container.mainContext
        // A household whose zone owner is reported as something *other* than the id the owner filed their
        // record under. That disagreement is exactly what this feature used to depend on not happening, and
        // when it did happen the record arrived, the name was stored, and the line stayed blank.
        let mismatched = Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_some-other-id"),
            title: "ignored"
        )
        let record = CKRecord(
            recordType: SharedWeekZone.RecordType.member,
            recordID: CKRecord.ID(recordName: "_sara", zoneID: mismatched.zoneID)
        )
        record[SharedWeekZone.MemberKey.displayName] = "Sara Parsons"
        record[SharedWeekZone.MemberKey.isOwner] = 1

        HouseholdInbox(context: context).apply(record, in: mismatched)

        #expect(HouseholdMembers.shared.owner(of: mismatched) == "Sara Parsons")
        #expect(try HouseholdInbox(context: context).member(authorID: "_sara", in: mismatched)?.isOwner == true)
    }

    @Test("A member who does not host is not taken for the owner")
    func aPlainMemberIsNotTheOwner() {
        let defaults = makeDefaults()
        let members = HouseholdMembers(defaults: defaults)
        // Their name is known — it labels their recipes — but they do not identify the household.
        members.record(id: "_leon", name: "Leon Parsons")
        #expect(members.name(for: "_leon") == "Leon Parsons")
        #expect(members.owner(of: parsons) == nil)
    }

    @Test("The owner's name is filed against the household, so two households keep their own")
    func ownersAreKeptPerHousehold() {
        let members = HouseholdMembers(defaults: makeDefaults())
        let other = Household(
            zoneID: CKRecordZone.ID(zoneName: SharedWeekZone.zoneName, ownerName: "_grandma"),
            title: "ignored"
        )
        members.recordOwner(of: parsons.id, name: "Sara Parsons")
        members.recordOwner(of: other.id, name: "Jean Hughes")

        #expect(members.owner(of: parsons) == "Sara Parsons")
        #expect(members.owner(of: other) == "Jean Hughes")
    }

    @Test("Somebody who has not said reads as nothing at all, never as a guess")
    func anUnnamedPersonSaysNothing() {
        let members = HouseholdMembers(defaults: makeDefaults())
        #expect(members.owner(of: parsons) == nil)
        #expect(members.owners.isEmpty)
        #expect(members.name(for: "_sara") == nil)
        #expect(members.name(for: "") == nil)
    }

    @Test("A name survives a relaunch — it can arrive long after the recipes do")
    func namesArePersisted() {
        let defaults = makeDefaults()
        HouseholdMembers(defaults: defaults).record(id: "_sara", name: "Sara Parsons")
        #expect(HouseholdMembers(defaults: defaults).name(for: "_sara") == "Sara Parsons")
    }

    @Test("A blank name is not a name, and never overwrites one")
    func blanksAreIgnored() {
        let members = HouseholdMembers(defaults: makeDefaults())
        members.record(id: "_sara", name: "Sara Parsons")
        members.record(id: "_sara", name: "   ")
        #expect(members.name(for: "_sara") == "Sara Parsons")
    }

    @Test("Signing out forgets who everybody else was")
    func forgettingClearsThem() {
        let defaults = makeDefaults()
        let members = HouseholdMembers(defaults: defaults)
        members.record(id: "_sara", name: "Sara Parsons")
        members.recordOwner(of: parsons.id, name: "Sara Parsons")
        members.forget()

        #expect(members.name(for: "_sara") == nil)
        #expect(members.owner(of: parsons) == nil)
        #expect(HouseholdMembers(defaults: defaults).name(for: "_sara") == nil)
    }

    // MARK: This device's own name

    @Test("Your own name is kept, trimmed, and cleared by an empty one")
    func theAuthorsNameIsStored() {
        let defaults = makeDefaults()
        let author = HouseholdAuthor(defaults: defaults)
        #expect(author.name == nil)

        author.setName("  Leon Parsons  ")
        #expect(author.name == "Leon Parsons")
        #expect(HouseholdAuthor(defaults: defaults).name == "Leon Parsons")

        author.setName("")
        #expect(author.name == nil)
    }

    @Test("Signing out of iCloud keeps your name — it is yours, not the account's")
    func forgettingKeepsTheName() {
        let author = HouseholdAuthor(defaults: makeDefaults())
        author.setName("Leon Parsons")
        author.forget()

        // The id goes, because the next account has its own. Asking again for a name they already gave would
        // be asking twice for the same answer.
        #expect(author.id == nil)
        #expect(author.name == "Leon Parsons")
    }
}
