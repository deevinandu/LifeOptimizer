import ARKit
import SwiftData
import SwiftUI

/// First-launch setup: calibrate a personal baseline, then configure an
/// emergency contact. Shown once (gated by `hasCompletedOnboarding` in
/// RootView) -- every later launch goes straight to RootTabView and just
/// monitors silently in the background. Demo mode (Home's Normal / Facial
/// Anomaly / Medium / High buttons) stays available afterward regardless,
/// for presenting without waiting on a real 30-second calibration.
struct OnboardingView: View {
    let onComplete: () -> Void

    private enum Step {
        case baseline
        case contact
    }

    @State private var step: Step = .baseline

    var body: some View {
        switch step {
        case .baseline:
            BaselineCalibrationStep {
                step = .contact
            }
        case .contact:
            EmergencyContactStep {
                onComplete()
            }
        }
    }
}

// MARK: - Step 1: Baseline Calibration

private struct BaselineCalibrationStep: View {
    let onFinished: () -> Void

    /// Matches BaselineEngine's warm-up window: `bootstrapThreshold` (10)
    /// normal samples at the current `fusionInterval` (0.2s) is ~2s in
    /// theory; padded to 8s for real-world margin (tracking hiccups,
    /// slower ticks) since undercounting just means a slightly-immature
    /// baseline, not a hard failure. The real engine is already collecting
    /// samples in the background the moment monitoring starts
    /// (LifeOptimizerApp starts it at launch) -- this countdown is just
    /// the UI wrapper around that warm-up window, not a separate mechanism.
    private let calibrationSeconds = 8

    @State private var remainingSeconds: Int?
    @State private var timerTask: Task<Void, Never>?

    private var isARKitSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressDots(step: 1, total: 2)

            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Set up your personal baseline")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if isARKitSupported {
                Text("Hold your phone up so your face is in view of the front camera. This takes about 30 seconds and only needs to happen once -- LifeOptimizer compares future readings against *your* normal, not anyone else's.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Baseline calibration uses the front TrueDepth camera, which the Simulator doesn't have. This step is skipped here -- it'll run for real the first time you launch on a physical iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let remainingSeconds {
                VStack(spacing: 8) {
                    ProgressView(value: Double(calibrationSeconds - remainingSeconds), total: Double(calibrationSeconds))
                        .padding(.horizontal, 40)
                    Text("\(remainingSeconds)s remaining")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                if isARKitSupported {
                    Button(remainingSeconds == nil ? "Start Calibration" : "Calibrating…") {
                        startCalibration()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(remainingSeconds != nil)
                } else {
                    Button("Continue") { onFinished() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }

                Button("Skip for now") { onFinished() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
        .onDisappear { timerTask?.cancel() }
    }

    private func startCalibration() {
        guard remainingSeconds == nil else { return }
        remainingSeconds = calibrationSeconds
        timerTask = Task { @MainActor in
            while let current = remainingSeconds, current > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remainingSeconds = current - 1
            }
            onFinished()
        }
    }
}

// MARK: - Step 2: Emergency Contact

private struct EmergencyContactStep: View {
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var contacts: [EmergencyContactRecord]

    @State private var name: String = ""
    @State private var phone: String = ""

    private enum Field { case name, phone }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressDots(step: 2, total: 2)

            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Add an emergency contact")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("If a HIGH-confidence event is detected, LifeOptimizer surfaces this contact's info alongside the simulated emergency workflow. You can change this anytime in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .phone)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button("Save & Finish Setup") {
                    saveContact()
                    onFinished()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(name.isEmpty && phone.isEmpty)

                Button("Skip for now") { onFinished() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private func saveContact() {
        guard !name.isEmpty || !phone.isEmpty else { return }
        if let existing = contacts.first {
            existing.name = name
            existing.phone = phone
        } else {
            modelContext.insert(EmergencyContactRecord(name: name, phone: phone))
        }
        try? modelContext.save()
    }
}

// MARK: - Shared

private struct ProgressDots: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { i in
                Circle()
                    .fill(i <= step ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
