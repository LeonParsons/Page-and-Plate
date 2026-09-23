import RecipeCore
import SwiftUI

/// SPEC §4 Settings: default Reminders list and the staples list.
struct SettingsView: View {
    @Environment(ExportSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(ScanQuota.self) private var quota
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let store: any RemindersStoring

    @State private var lists: [ReminderList] = []
    @State private var access: RemindersAccess = .notDetermined
    @State private var newStaple = ""
    @State private var isShowingPaywall = false
    @State private var isManagingSubscription = false
    @State private var cloud = CloudAccount()
    @Environment(SharedWeekPublisher.self) private var sharedPlan
    @AppStorage(WelcomeView.hasSeenKey) private var hasSeenWelcome = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Scans", value: quota.statusText)
                    if subscriptions.isSubscribed {
                        if let ends = subscriptions.expirationDate {
                            LabeledContent("Unlimited", value: "until \(ends.formatted(date: .abbreviated, time: .omitted))")
                        }
                        Button("Manage subscription") { isManagingSubscription = true }
                    } else {
                        Button("Get Unlimited…") { isShowingPaywall = true }
                    }
                    Button("Restore purchases") {
                        Task { await subscriptions.restore() }
                    }
                    #if DEBUG
                    Button("Use up free scans (debug)") { quota.useUpFreeScans() }
                    Button("Reset free scans (debug)") { quota.resetFreeScans() }
                    #endif
                } header: {
                    Text("Scans")
                } footer: {
                    Text("A scan is one photographed recipe. \(ScanAllowance.freeScans) are free every 30 days; Unlimited removes the limit.")
                }

                Section {
                    LabeledContent("iCloud", value: cloud.statusText)
                } header: {
                    Text("Sync")
                } footer: {
                    Text(cloud.detailText)
                }

                #if DEBUG
                // Phase 10 step 1: proves a CKSyncEngine can run in the same container SwiftData mirrors.
                // Replaced by the real "Share this plan…" entry in step 2.
                Section("Shared plan (debug)") {
                    LabeledContent("Publisher", value: sharedPlan.statusText)
                    Button("Publish the plan") {
                        Task {
                            await sharedPlan.start()
                            try? sharedPlan.publish(from: modelContext)
                        }
                    }
                }
                #endif

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
                    Text("The list chosen at export is remembered as the default.")
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
                    Text("Staples are unticked by default when adding to Reminders. Matched against the ingredient name exactly, ignoring case.")
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
            .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        }
    }

    private var serverDescription: String {
        (try? AppConfiguration.loadFromMainBundle().apiBaseURL.host()) ?? "not configured"
    }

    private func addStaple() {
        settings.addStaple(newStaple)
        newStaple = ""
    }
}
