// LifeOptimizerApp.swift
// LifeOptimizer — App Entry Point

import SwiftUI
import SwiftData

@main
struct LifeOptimizerApp: App {

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: PersistedBaselineFeature.self,
                     PersistedBenignAnomaly.self,
                     PersistedDetectionEvent.self,
                     UserProfile.self
            )
        } catch {
            fatalError("[LifeOptimizer] SwiftData container failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
