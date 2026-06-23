// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+LogsTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

extension AdminView {
    var logsTab: some View {
        NavigationStack {
            List {
                cachePerformanceSection
                promotedTilesSection
                activityLogSection
                sentenceCacheSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Logs")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Logs", systemImage: "list.bullet.rectangle.fill") }
    }

    // MARK: - Promoted tiles helpers

    func promotedTileRow(_ entry: SentenceCache) -> some View {
        HStack(spacing: 10) {
            TileGridIcon(tiles: tileSelections(for: entry))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.sentence)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(entry.hitCount) hits")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Cache Stats

    var cacheStatsView: some View {
        let hits = cacheHitCount
        let misses = cacheMissCount
        let total = hits + misses
        let hitRate = total > 0 ? Double(hits) / Double(total) * 100 : 0
        let missRate = total > 0 ? Double(misses) / Double(total) * 100 : 0

        return Group {
            HStack {
                StatBox(label: "Lookups", value: "\(total)", color: .primary)
                StatBox(label: "Hits", value: "\(hits)", color: .green)
                StatBox(label: "Misses", value: "\(misses)", color: .orange)
            }

            HStack {
                StatBox(label: "Hit Rate", value: String(format: "%.1f%%", hitRate), color: .green)
                StatBox(label: "Miss Rate", value: String(format: "%.1f%%", missRate), color: .orange)
                StatBox(label: "Entries", value: "\(cacheEntries.count)", color: .blue)
            }

            if total == 0 {
                Text("No lookups recorded yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func deleteCacheEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cacheEntries[index])
        }
        try? modelContext.save()
    }

    func flushAllCache() {
        for entry in cacheEntries {
            modelContext.delete(entry)
        }
        // Clear cache-related metric events so stats reset with the cache
        for event in allMetricEvents where
            (event.subjectType == "cache" && event.eventType == .hit) ||
            (event.subjectType == "sentence" && event.eventType == .used) {
            modelContext.delete(event)
        }
        try? modelContext.save()
    }

    // MARK: - Sections

    @ViewBuilder
    var cachePerformanceSection: some View {
        Section {
            cacheStatsView
        } header: {
            Text("Cache Performance")
        }
    }

    @ViewBuilder
    var promotedTilesSection: some View {
        Section {
            if promotedCandidates.isEmpty {
                Text("No promoted tiles yet — use the same tile combo 3+ times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(promotedCandidates.prefix(5)) { entry in
                    promotedTileRow(entry)
                }
                if promotedCandidates.count > 5 {
                    NavigationLink {
                        PromotedTilesDetailView(entries: promotedCandidates, tileLookup: tileLookup)
                    } label: {
                        Text("View All (\(promotedCandidates.count))")
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Promoted Tiles (\(promotedCandidates.count))")
        }
    }

    @ViewBuilder
    var activityLogSection: some View {
        Section {
            NavigationLink {
                ActivityLogView()
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                    Text("View Activity Log")
                }
            }
        } header: {
            Text("Activity Log")
        } footer: {
            Text("Finalized utterances from the sentence tray, grouped by day. Read-only review for therapists and partners.")
        }
    }

    @ViewBuilder
    var sentenceCacheSection: some View {
        Section {
            NavigationLink {
                CacheDetailView(entries: cacheEntries, onDelete: deleteCacheEntries, onFlush: flushAllCache)
            } label: {
                Text("View \(cacheEntries.count) entries")
            }
            .disabled(cacheEntries.isEmpty)
        } header: {
            HStack {
                Text("Sentence Cache (\(cacheEntries.count))")
                Spacer()
                if !cacheEntries.isEmpty {
                    Button("Flush All", role: .destructive) {
                        flushAllCache()
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    var developerSection: some View {
        Section("Developer") {
            Toggle("Show Nav Menu", isOn: $devShowNav)
            if isResetting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Resetting…").foregroundStyle(.secondary)
                }
            } else {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Factory Reset", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .confirmationDialog("Factory Reset", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset All Data", role: .destructive) { performFactoryReset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes all scenes, pages, tiles, and cache. Vocabulary reloads from the bundle.")
        }
    }

    func performFactoryReset() {
        isResetting = true
        sentenceEngine.clearSelection()
        do {
            // BlasterScene.pages is inline JSON-encoded data (no PageModel
            // relationship), so deleting BlasterScene is sufficient.
            try modelContext.delete(model: MetricEvent.self)
            try modelContext.delete(model: SentenceCache.self)
            try modelContext.delete(model: BlasterScene.self)
            try modelContext.delete(model: TileModel.self)
            try modelContext.delete(model: ChildProfile.self)
            try modelContext.delete(model: DeviceProfile.self)
            try modelContext.save()
        } catch {
            print("Factory reset failed: \(error)")
            isResetting = false
            return
        }
        // Clear all bootstrap-state flags so the next loadDefaultVocabulary
        // call writes fresh hash + installed flag via markBootstrapComplete.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppSettingsKey.bootstrapInstalled)
        defaults.removeObject(forKey: AppSettingsKey.bootstrapContentHash)
        defaults.removeObject(forKey: AppSettingsKey.bootstrapVersion)
        _ = BootstrapLoader.loadDefaultVocabulary(context: modelContext)
        BootstrapLoader.markBootstrapComplete()
        // Match cold-launch behavior: re-seed the DeviceProfile placeholder
        // and the Sandbox ChildProfile so the user lands in the same state
        // as a fresh install. Without this, the Admin Profiles list comes
        // back empty after a reset and the resolver has nothing to fall
        // back to until OnboardingCommit creates a real profile.
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: modelContext,
            seedLegacy: false
        )
        profileResolver.refresh()
        isResetting = false
    }
    #endif
}
