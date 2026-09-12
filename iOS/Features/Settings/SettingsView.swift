import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var contacts: [EmergencyContactRecord]

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var carrier: MobileCarrier?
    // `@AppStorage` persists to UserDefaults, so this survives app relaunches
    // -- a plain `@State` here (as before) reset to the hardcoded default
    // every time the app restarted, which is why "Apply" never seemed to
    // stick. `LifeOptimizerApp.init()` reads this same key to seed the
    // actual APIClient at launch, not just while this screen is open.
    @AppStorage("backendURLString") private var backendURLString: String = "http://127.0.0.1:8000"

    /// The person being monitored -- included in the emergency alert text
    /// so it says who it's about, not just a generic "possible stroke
    /// detected". Same @AppStorage/UserDefaults key EmergencyManager reads.
    @AppStorage("patientName") private var patientName: String = "Malavika Mohan"

    @State private var saveConfirmation: String?

    // `.phonePad` (and `.numberPad`) have no Return/Done key on iOS -- without
    // an explicit way to resign focus, the keyboard stays up forever and
    // covers the tab bar, making the whole app look stuck. This toolbar
    // button is that explicit way out.
    private enum Field { case name, phone, backendURL, patientName }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $patientName)
                        .focused($focusedField, equals: .patientName)
                } header: {
                    Text("Your info")
                } footer: {
                    Text("Included in the emergency alert text so it identifies who it's about.")
                }

                Section {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                    Picker("Carrier", selection: $carrier) {
                        Text("Not set").tag(MobileCarrier?.none)
                        ForEach(MobileCarrier.allCases) { c in
                            Text(c.label).tag(MobileCarrier?.some(c))
                        }
                    }
                    Button("Save contact") { saveContact() }
                } header: {
                    Text("Emergency contact")
                } footer: {
                    Text("Carrier is used to text this contact via their carrier's email-to-SMS gateway (see backend/.env.example).")
                }

                Section {
                    TextField("Backend URL", text: $backendURLString)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .backendURL)
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .onAppear {
                if let existing = contacts.first {
                    name = existing.name
                    phone = existing.phone
                    carrier = existing.carrier.flatMap(MobileCarrier.init(rawValue:))
                }
            }
            .alert(saveConfirmation ?? "", isPresented: Binding(
                get: { saveConfirmation != nil },
                set: { if !$0 { saveConfirmation = nil } }
            )) {
                Button("OK") {}
            }
        }
    }

    private func saveContact() {
        if let existing = contacts.first {
            existing.name = name
            existing.phone = phone
            existing.carrier = carrier?.rawValue
        } else {
            modelContext.insert(EmergencyContactRecord(name: name, phone: phone, carrier: carrier?.rawValue))
        }
        do {
            try modelContext.save()
            saveConfirmation = "Contact saved."
        } catch {
            // Previously `try?` here silently swallowed any save failure --
            // if this fires, that's the real reason "the contact doesn't
            // save" instead of a UI/timing issue.
            saveConfirmation = "Failed to save contact: \(error.localizedDescription)"
        }
    }

    private func applyBackendURL() {
        guard let url = URL(string: backendURLString) else {
            saveConfirmation = "That's not a valid URL."
            return
        }
        AppEnvironment.shared.apiClient?.baseURL = url
        saveConfirmation = "Backend URL applied: \(url.absoluteString)"
    }
}
