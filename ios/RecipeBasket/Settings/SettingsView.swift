import RecipeCore
import SwiftUI

/// SPEC §4 Settings: default Reminders list and the staples list.
struct SettingsView: View {
    @Environment(ExportSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let store: any RemindersStoring

    @State private var lists: [ReminderList] = []
    @State private var access: RemindersAccess = .notDetermined
    @State private var newStaple = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
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

                Section("Server") {
                    LabeledContent("Extraction API", value: serverDescription)
                }
            }
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
