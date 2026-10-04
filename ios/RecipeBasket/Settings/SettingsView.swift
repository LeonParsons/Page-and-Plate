import CloudKit
import RecipeCore
import SwiftUI

/// SPEC §4 Settings: default Reminders list and the staples list.
struct SettingsView: View {
    @Environment(ExportSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(ScanQuota.self) private var quota
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    /// This device's own library, which `HouseholdDemoSeed` projects the demo household from.
    @Environment(\.modelContext) private var modelContext
    #endif
    let store: any RemindersStoring
    /// Households. Optional for the same reason it is everywhere else: the app works without the household
    /// store, it simply cannot share.
    var plan: SharedPlanContext?

    @State private var lists: [ReminderList] = []
    @State private var access: RemindersAccess = .notDetermined
    @State private var newStaple = ""
    @State private var isShowingPaywall = false
    @State private var isManagingSubscription = false
    @State private var cloud = CloudAccount()
    /// Owned here, not by `SharePlanSection`: the sharing sheet has to hang off the `Form`, like the paywall.
    @State private var sharePresentation: SharePresentation?
    @AppStorage(WelcomeView.hasSeenKey) private var hasSeenWelcome = false
    #if DEBUG
    /// What "Check the App Store (debug)" last found. See `StoreCheck`.
    @State private var storeCheck: String?
    #endif

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Scans", value: quota.statusText)
                    if subscriptions.standing.isAtRisk {
                        // Said plainly and early, because the household goes with the subscription — and the
                        // only person who can fix it is the one reading this.
                        LabeledContent("Subscription", value: "Needs attention")
                            .foregroundStyle(Brand.tomato)
                        Button("Manage subscription") { isManagingSubscription = true }
                    } else if subscriptions.isSubscribed {
                        if let ends = subscriptions.expirationDate {
                            LabeledContent("Subscription", value: "until \(ends.formatted(date: .abbreviated, time: .omitted))")
                        }
                        Button("Manage subscription") { isManagingSubscription = true }
                    } else {
                        Button("Subscribe…") { isShowingPaywall = true }
                    }
                    Button("Restore purchases") {
                        Task { await subscriptions.restore() }
                    }
                    #if DEBUG
                    Button("Use up scans (debug)") { quota.useUpScans() }
                    Button("Reset scans (debug)") { quota.resetScans() }
                    // Reset scans clears only this phone's own tally; the Worker goes on counting against the
                    // attested key, or the device id when a scan is not attested. Forgetting both makes the next
                    // scan come from a new device, which is what a demo on a well-used phone needs. Install the
                    // TestFlight build afterwards and it attests a fresh production key.
                    Button("Start over as a new device (debug)") {
                        quota.resetScans()
                        DeviceIdentity.forget()
                        AppAttest.forgetKey()
                    }
                    // Lets a device host a household before the products exist in App Store Connect. It does
                    // not grant scans: the Worker still sees no entitlement and still applies the free trial.
                    Toggle("Pretend subscribed (debug)", isOn: Binding(
                        get: { quota.pretendsSubscribed },
                        set: { quota.setPretendSubscribed($0) }
                    ))
                    // A build installed with `devicectl` asks the real sandbox, not RecipeBasket.storekit, so this
                    // is what TestFlight and App Review are offered too.
                    Button("Check the App Store (debug)") {
                        Task { storeCheck = await StoreCheck.run() }
                    }
                    if let storeCheck {
                        Text(storeCheck)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    #endif
                } header: {
                    Text("Scans")
                } footer: {
                    if case .atRisk(let until) = subscriptions.standing {
                        Text(riskText(until: until))
                    } else {
                        Text("A scan is one photographed recipe. The first \(ScanAllowance.trialScans) are free. A subscription covers everything you cook in a week.")
                    }
                }

                Section {
                    Picker("Week starts on", selection: $settings.weekStartsOn) {
                        // 1 = Sunday … 7 = Saturday, the order `Calendar.standaloneWeekdaySymbols` uses.
                        ForEach(1...7, id: \.self) { weekday in
                            Text(ExportSettings.weekdayName(weekday)).tag(weekday)
                        }
                    }
                } header: {
                    Text("Week")
                } footer: {
                    Text("Set this to the day you shop, so the week you plan is the week you buy for.")
                }

                Section {
                    LabeledContent("iCloud", value: cloud.statusText)
                } header: {
                    Text("Sync")
                } footer: {
                    Text(cloud.detailText)
                }

                if let plan {
                    SharePlanSection(plan: plan, presenting: $sharePresentation, onPaywall: { isShowingPaywall = true })
                    #if DEBUG
                    // The household is the one screen a simulator cannot reach — hosting needs an iCloud
                    // account and a subscription — so the App Store frame for it had no way to be shot, or
                    // reshot when copy changed. See `HouseholdDemoSeed`.
                    Section {
                        Button("Seed demo household (debug)") {
                            HouseholdDemoSeed.seed(plan: plan, library: modelContext)
                            dismiss()
                        }
                        Button("Clear demo household (debug)", role: .destructive) {
                            HouseholdDemoSeed.clear(plan: plan)
                        }
                    } footer: {
                        Text("Projects this device's own recipes into a demo household, so the household screens can be photographed. `marketing/README.md` says how the frames are made.")
                    }
                    #endif
                }

                Section {
                    if access == .fullAccess {
                        Picker("Default list", selection: $settings.defaultListID) {
                            Text("Ask each time").tag(String?.none)
                            ForEach(lists) { list in
                                Text(list.sourceTitle.isEmpty ? list.title : "\(list.title) (\(list.sourceTitle))").tag(String?.some(list.id))
                            }
                        }
                    } else {
                        LabeledContent("Default list", value: access == .writeOnly ? "Reminders default" : "Needs Reminders access")
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("The list chosen at export is remembered as the default.\n\n\(ReminderListPicker.groceriesTip)")
                }

                Section {
                    ForEach(settings.staples, id: \.self) { staple in
                        Text(staple)
                    }
                    .onDelete { offsets in
                        for offset in offsets { settings.removeStaple(settings.staples[offset]) }
                    }
                    HStack {
                        TextField("Add a staple, e.g. sea salt", text: $newStaple)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addStaple)
                        Button("Add", action: addStaple)
                            .disabled(newStaple.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Staples")
                } footer: {
                    Text("Staples are unticked by default when adding to Reminders.")
                }

                Section {
                    Button("Restore default staples") { settings.restoreDefaultStaples() }
                }

                Section("About") {
                    Button("Show welcome screen") {
                        dismiss()
                        hasSeenWelcome = false
                    }
                    LabeledContent("Extraction API", value: serverDescription)
                }
            }
            .paperBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                access = store.authorizationStatus()
                lists = access == .fullAccess ? store.lists() : []
            }
            .task { await cloud.refresh() }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .sheet(item: $sharePresentation) { presentation in
                CloudSharingSheet(share: presentation.share, container: CKContainer(identifier: AppModelContainer.cloudKitContainerID))
                    .ignoresSafeArea()
            }
            .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        }
    }

    /// What an at-risk subscription means for the household, with a date when Apple gives one.
    private func riskText(until: Date?) -> String {
        let base = "There's a problem with your payment. Your household keeps working while it's sorted out"
        guard let until else { return base + " — nobody else is told." }
        return base + " until \(until.formatted(date: .abbreviated, time: .omitted)) — nobody else is told."
    }

    private var serverDescription: String {
        (try? AppConfiguration.loadFromMainBundle().apiBaseURL.host()) ?? "not configured"
    }

    private func addStaple() {
        settings.addStaple(newStaple)
        newStaple = ""
    }
}
