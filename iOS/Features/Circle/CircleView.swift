import CoreLocation
import MapKit
import SwiftUI
import VisionKit

/// Trusted Circle: an opt-in, from-scratch equivalent to "notify whoever's
/// nearby" -- Apple's Find My doesn't expose any public API for reading
/// who has shared their location with a user, so this is built entirely
/// within LifeOptimizer's own accounts-free model instead. Two roles, both
/// available on this one screen since either device might play either role:
///
///   - As a PATIENT: share your code, see who's joined your circle.
///   - As a MEMBER (of someone else's circle): join with their code --
///     `CircleLocationTracker` then reports your location continuously in
///     the background (not just while this screen is open), because a
///     manual "refresh" model doesn't make sense here: whoever was
///     nearby the last time you happened to tap refresh might not be
///     nearby anymore by the time an actual emergency happens.
struct CircleView: View {
    @State private var locationManager = LocationManager()
    @ObservedObject private var tracker = CircleLocationTracker.shared

    @State private var members: [CircleMember] = []
    @State private var isLoadingMembers = false

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var myCoordinate: CLLocationCoordinate2D?
    @State private var myLocationError: String?

    @AppStorage("joinedCircleId") private var joinedCircleId: String = ""
    @AppStorage("joinedCircleMemberId") private var joinedCircleMemberId: String = ""

    @State private var joinCode = ""
    // Persistent, not per-join @State -- this is *your* identity when you
    // join someone else's circle, and it doesn't change from one circle to
    // the next, so it shouldn't have to be retyped every time either.
    // Editable here if it's ever wrong, but pre-filled from here on.
    // Same UserDefaults key as Settings' "Your name" field -- previously
    // this read a *different* key ("myCircleName") that Settings never
    // actually wrote to, so a name change in Settings would never show up
    // here. Read-only here (no editing UI in this view), so @AppStorage's
    // live-reflects-UserDefaults behavior is exactly what's wanted.
    @AppStorage("patientName") private var joinName: String = "Malavika Mohan"
    @AppStorage("myCirclePhone") private var joinPhone: String = ""
    @AppStorage("myCircleCarrierRaw") private var joinCarrierRaw: String = ""
    @State private var joinStatus: String?
    @State private var isJoining = false
    @State private var showScanner = false
    @State private var scannerUnavailableMessage: String?
    /// Set when the code came from actually scanning a QR (which carries
    /// the patient's name/phone/carrier) rather than manual entry (which
    /// only ever has the bare ID) -- reciprocal circle membership is only
    /// possible when this is set, since manual entry has nothing to
    /// reciprocate with.
    @State private var scannedInvite: CircleInvitePayload?

    private enum Field { case joinCode }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Map(position: $cameraPosition) {
                        if let myCoordinate {
                            Marker("You", systemImage: "location.fill", coordinate: myCoordinate)
                                .tint(.blue)
                        }
                        ForEach(members) { member in
                            if let lat = member.latitude, let lon = member.longitude {
                                Marker(member.name, systemImage: "person.fill", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                    .tint(.orange)
                            }
                        }
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                    Button("Refresh my location") { Task { await refreshMyLocation() } }
                    if let myLocationError {
                        Text(myLocationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Map")
                } footer: {
                    Text("Only shows circle members with a reported location -- someone who hasn't opened their app recently (or hasn't granted \"Always\" location access) won't appear, or will show a stale position.")
                }

                Section {
                    if let qrImage = QRCodeGenerator.image(from: QRCodeGenerator.joinPayload(CircleInvitePayload(
                        patientId: AppEnvironment.patientId,
                        name: joinName,
                        phone: joinPhone.isEmpty ? nil : joinPhone,
                        carrier: joinCarrierRaw.isEmpty ? nil : joinCarrierRaw
                    ))) {
                        HStack {
                            Spacer()
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 180, height: 180)
                            Spacer()
                        }
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                    }
                    Text(AppEnvironment.patientId)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    ShareLink(item: "Join my LifeOptimizer Trusted Circle with this code: \(AppEnvironment.patientId)") {
                        Label("Share your code", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Your circle code")
                } footer: {
                    Text("Have someone you trust scan this QR code (or share/type the code) to join. If they're nearby during a HIGH-confidence event, they get alerted too -- even though they're not your designated emergency contact.")
                }

                Section {
                    if isLoadingMembers {
                        ProgressView()
                    } else if members.isEmpty {
                        Text("No one has joined your circle yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                if let lat = member.latitude, let lon = member.longitude {
                                    Text(String(format: "Last seen: %.3f, %.3f", lat, lon))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No location reported yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button("Refresh") { Task { await loadMembers() } }
                } header: {
                    Text("Members in your circle")
                }

                Section {
                    if joinedCircleId.isEmpty {
                        // Your identity is set once in Settings and reused
                        // for every circle you join -- no reason to
                        // re-enter it here every time.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Joining as").font(.caption).foregroundStyle(.secondary)
                            Text(identitySummary)
                        }
                        if joinPhone.isEmpty || joinCarrierRaw.isEmpty {
                            Text("Add your phone number and carrier in Settings so you can actually be texted if you turn out to be the nearest circle member.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            presentScanner()
                        } label: {
                            Label("Scan their QR code", systemImage: "qrcode.viewfinder")
                        }
                        if let scannerUnavailableMessage {
                            Text(scannerUnavailableMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Or enter circle code manually", text: $joinCode)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .joinCode)

                        Button {
                            Task { await join() }
                        } label: {
                            if isJoining {
                                ProgressView()
                            } else {
                                Text("Join circle")
                            }
                        }
                        .disabled(isJoining || joinCode.isEmpty)
                    } else {
                        trackingStatusView
                        Button("Leave circle", role: .destructive) {
                            tracker.stop()
                            joinedCircleId = ""
                            joinedCircleMemberId = ""
                            joinStatus = nil
                        }
                    }
                    if let joinStatus {
                        Text(joinStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Join someone else's circle")
                } footer: {
                    Text("Once joined, your location is shared continuously in the background (not just while this app is open) -- if it only shows \"foreground only\" below, grant \"Always\" location access in Settings so it keeps working when your phone is in your pocket.")
                }
            }
            .navigationTitle("Trusted Circle")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .task {
                await loadMembers()
                await refreshMyLocation()
            }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { payload in
                        let invite = QRCodeGenerator.parseInvite(fromScanned: payload)
                        scannedInvite = invite
                        joinCode = invite.patientId
                        showScanner = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan Circle Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showScanner = false }
                        }
                    }
                }
            }
        }
    }

    private func presentScanner() {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            // Not available on Simulator (no camera) or on some older
            // devices -- manual entry below still works either way.
            scannerUnavailableMessage = "Camera scanning isn't available on this device -- enter the code manually below instead."
            return
        }
        scannerUnavailableMessage = nil
        showScanner = true
    }

    @ViewBuilder
    private var trackingStatusView: some View {
        Label(
            tracker.isBackgroundCapable ? "Sharing location continuously" : "Sharing location (foreground only)",
            systemImage: tracker.isBackgroundCapable ? "location.fill" : "location"
        )
        .foregroundStyle(tracker.isBackgroundCapable ? .green : .orange)

        if let lastSentAt = tracker.lastSentAt {
            Text("Last sent: \(lastSentAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let trackerError = tracker.lastError {
            Text(trackerError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func refreshMyLocation() async {
        do {
            myCoordinate = try await locationManager.currentLocation()
            myLocationError = nil
        } catch {
            // Previously silently swallowed (`try?`) -- if "You" never
            // shows up on the map, this is why: permission denied, no GPS
            // fix yet, or (on Simulator) no location set under
            // Features -> Location.
            myLocationError = "Couldn't get your location: \(error.localizedDescription)"
        }
    }

    private func loadMembers() async {
        guard let apiClient = AppEnvironment.shared.apiClient else { return }
        isLoadingMembers = true
        defer { isLoadingMembers = false }
        do {
            members = try await apiClient.getCircleMembers(patientId: AppEnvironment.patientId)
        } catch {
            // Non-fatal -- just leave the list as-is (likely empty on first load).
            print("[CircleView] Failed to load members: \(error)")
        }
    }

    private var identitySummary: String {
        var parts = [joinName]
        if !joinPhone.isEmpty { parts.append(joinPhone) }
        if let carrier = MobileCarrier(rawValue: joinCarrierRaw) { parts.append(carrier.label) }
        return parts.joined(separator: " · ")
    }

    private func join() async {
        guard let apiClient = AppEnvironment.shared.apiClient else { return }
        guard !joinCode.isEmpty, !joinName.isEmpty else {
            joinStatus = "Enter a code and your name."
            return
        }
        isJoining = true
        defer { isJoining = false }
        do {
            let response = try await apiClient.joinCircle(
                patientId: joinCode,
                request: JoinCircleRequest(
                    name: joinName,
                    phone: joinPhone.isEmpty ? nil : joinPhone,
                    carrier: joinCarrierRaw.isEmpty ? nil : joinCarrierRaw,
                    memberDeviceId: AppEnvironment.patientId
                )
            )
            joinedCircleId = joinCode
            joinedCircleMemberId = response.memberId
            tracker.start(patientId: joinCode, memberId: response.memberId)

            // Reciprocal: if this code came from actually scanning their
            // QR (which carries their name/phone/carrier), also add them
            // to *my* circle -- not just me to theirs. Manual code entry
            // has nothing to reciprocate with (just a bare ID), so this
            // only happens via a real scan, and only if the scanned code
            // is still the one we're joining (guards against joinCode
            // having been hand-edited after scanning something else).
            if let invite = scannedInvite, invite.patientId == joinCode {
                do {
                    _ = try await apiClient.joinCircle(
                        patientId: AppEnvironment.patientId,
                        request: JoinCircleRequest(
                            name: invite.name,
                            phone: invite.phone,
                            carrier: invite.carrier,
                            memberDeviceId: invite.patientId
                        )
                    )
                    joinStatus = "Joined -- you're now in each other's circles."
                } catch {
                    // Non-fatal: the primary join above already succeeded,
                    // this is just the reciprocal half.
                    joinStatus = "Joined, but couldn't add you to their circle in return: \(error.localizedDescription)"
                }
            } else {
                joinStatus = nil
            }
        } catch {
            joinStatus = "Failed to join: \(error.localizedDescription)"
        }
    }
}
