// BaselineStore.swift
// LifeOptimizer — SwiftData Persistence Bridge for Baseline
//
// Loads persisted feature stats into BaselineEngine on startup,
// and saves the engine's state periodically or on demand.

import Foundation
import SwiftData

@MainActor
public final class BaselineStore {

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Load

    /// Restore all persisted baseline features into the given engine.
    public func load(into engine: BaselineEngine) throws {
        let descriptor = FetchDescriptor<PersistedBaselineFeature>()
        let persisted  = try modelContext.fetch(descriptor)
        let stats      = persisted.map { $0.toStat() }
        engine.restore(stats: stats)
        print("[BaselineStore] Loaded \(stats.count) feature stats.")
    }

    // MARK: - Save

    /// Persist the engine's current state. Upserts existing records.
    public func save(from engine: BaselineEngine) throws {
        let descriptor = FetchDescriptor<PersistedBaselineFeature>()
        let existing   = try modelContext.fetch(descriptor)
        var existingMap = [String: PersistedBaselineFeature]()
        for record in existing { existingMap[record.name] = record }

        for stat in engine.allStats {
            if let record = existingMap[stat.name] {
                record.apply(stat)
            } else {
                let newRecord = PersistedBaselineFeature(
                    name:        stat.name,
                    mean:        stat.mean,
                    variance:    stat.variance,
                    sampleCount: stat.sampleCount,
                    lastUpdated: stat.lastUpdated
                )
                modelContext.insert(newRecord)
            }
        }
        try modelContext.save()
    }

    // MARK: - Reset

    /// Wipe the entire stored baseline (user-initiated reset).
    public func reset() throws {
        try modelContext.delete(model: PersistedBaselineFeature.self)
        try modelContext.save()
        print("[BaselineStore] Baseline reset.")
    }
}
