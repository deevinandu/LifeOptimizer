// ContentView.swift
// LifeOptimizer — Debug / Demo View (Laptop A minimal UI)
//
// This is intentionally minimal. Laptop B owns the polished UI.
// This view exists only for Laptop A to verify the sensing pipeline works.

import SwiftUI

@MainActor
struct ContentView: View {

    // MARK: - State

    @State private var selectedScenario: DemoScenario = .normal
    @State private var stateMachine: DetectionStateMachine?
    @State private var latestResult: DetectionResult?
    @State private var isMonitoring = false
    @State private var eventLog: [String] = []
    @State private var listenTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // ── Mode picker ──────────────────────────────────────────
                Section("Demo Scenario") {
                    Picker("Scenario", selection: $selectedScenario) {
                        ForEach(DemoScenario.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isMonitoring)
                }

                // ── Controls ─────────────────────────────────────────────
                Section("Controls") {
                    Button(isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                        toggleMonitoring()
                    }
                    .foregroundStyle(isMonitoring ? .red : .green)

                    if isMonitoring && stateMachine?.currentState == .mediumConfidence {
                        HStack {
                            Button("I'm Okay") {
                                stateMachine?.submitUserResponse(.okay)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)

                            Button("I Need Help") {
                                stateMachine?.submitUserResponse(.needsHelp)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                }

                // ── Current Result ───────────────────────────────────────
                if let result = latestResult {
                    Section("Latest Detection Result") {
                        resultRow("Classification", result.classification.rawValue,
                                  color: color(for: result.classification))
                        resultRow("Final Score",   String(format: "%.2f", result.finalScore))
                        resultRow("Facial Score",  String(format: "%.2f", result.facialScore))
                        resultRow("Motion Score",  String(format: "%.2f", result.motionScore))
                        resultRow("Temporal Score",String(format: "%.2f", result.temporalScore))
                        resultRow("Depth Score",   String(format: "%.2f", result.depthScore))
                    }
                }

                // ── Event Log ────────────────────────────────────────────
                if !eventLog.isEmpty {
                    Section("Event Log (last 20)") {
                        ForEach(eventLog.suffix(20).reversed(), id: \.self) { entry in
                            Text(entry)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Baseline Info ─────────────────────────────────────────
                if let sm = stateMachine {
                    Section("Baseline") {
                        resultRow("Samples",
                            "\(sm.baselineEngine.totalSamples)",
                            color: .secondary)
                        resultRow("Calibrated",
                            sm.baselineEngine.isCalibrated ? "Yes ✓" : "Warming up…",
                            color: sm.baselineEngine.isCalibrated ? .green : .orange)
                    }
                }
            }
            .navigationTitle("LifeOptimizer")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Actions

    private func toggleMonitoring() {
        if isMonitoring {
            listenTask?.cancel()
            listenTask = nil
            stateMachine?.stopMonitoring()
            stateMachine   = nil
            isMonitoring   = false
            latestResult   = nil
        } else {
            let sm = DemoDataProvider.stateMachine(for: selectedScenario)
            stateMachine = sm
            isMonitoring = true
            sm.startMonitoring()
            listenToStreams(sm)
        }
    }

    private func listenToStreams(_ sm: DetectionStateMachine) {
        listenTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await result in sm.detectionStream {
                        guard !Task.isCancelled else { break }
                        latestResult = result
                    }
                }
                group.addTask { @MainActor in
                    for await event in sm.eventStream {
                        guard !Task.isCancelled else { break }
                        eventLog.append("[\(Date().formatted(date: .omitted, time: .shortened))] \(describe(event))")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func resultRow(_ label: String, _ value: String,
                            color: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).bold()
        }
    }

    private func color(for classification: DetectionClassification) -> Color {
        switch classification {
        case .normal: return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }

    private func describe(_ event: DetectionEvent) -> String {
        switch event {
        case .classificationChanged(let r):
            return "Classification: \(r.classification.rawValue) (\(String(format: "%.2f", r.finalScore)))"
        case .escalatedToMedium:
            return "⚠️ ESCALATED → MEDIUM"
        case .escalatedToHigh:
            return "🚨 ESCALATED → HIGH"
        case .resolvedToNormal:
            return "✅ Resolved → NORMAL"
        case .userConfirmedBenign:
            return "👍 User confirmed benign"
        }
    }
}

#Preview {
    ContentView()
}
