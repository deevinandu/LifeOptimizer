import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var contacts: [EmergencyContactRecord]

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var backendURLString: String = "http://127.0.0.1:8000"

    var body: some View {
        NavigationStack {
            Form {
                Section("Emergency contact") {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    Button("Save contact") { saveContact() }
                }

                Section {
                    TextField("Backend URL", text: $backendURLString)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Apply") { applyBackendURL() }
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Use your Mac's LAN IP (e.g. http://192.168.1.23:8000) when testing on a physical iPhone -- 127.0.0.1 only resolves to the backend from the iOS Simulator running on the same Mac.")
                }

                Section("Privacy") {
                    Text("Your personal baseline, facial data, depth data, and motion data stay on this device. Only emergency incident information (scores, classification, location, timestamp) is shared with the backend, and only when an emergency is triggered.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if let existing = contacts.first {
                    name = existing.name
                    phone = existing.phone
                }
            }
        }
    }

    private func saveContact() {
        if let existing = contacts.first {
            existing.name = name
            existing.phone = phone
        } else {
            modelContext.insert(EmergencyContactRecord(name: name, phone: phone))
        }
        try? modelContext.save()
    }

    private func applyBackendURL() {
        guard let url = URL(string: backendURLString) else { return }
        AppEnvironment.shared.apiClient?.baseURL = url
    }
}
