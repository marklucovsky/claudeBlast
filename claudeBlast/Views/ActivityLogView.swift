// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ActivityLogView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Therapist/partner-facing review log of finalized utterances. Read-only by design —
/// each row is what the child "said," when, plus an escalation badge when the same combo
/// was repeated. Logged at flush time in `SentenceEngine.flushActiveToHistory`.
struct ActivityLogView: View {
    @Query(sort: \LoggedUtterance.createdAt, order: .reverse)
    private var allEntries: [LoggedUtterance]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    @State private var filter: TimeFilter = .today

    enum TimeFilter: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Past Week"
        case all = "All Time"
        var id: String { rawValue }

        /// Lower bound (inclusive) for filtering; nil = no bound.
        func earliest(now: Date = .now) -> Date? {
            let cal = Calendar.current
            switch self {
            case .today: return cal.startOfDay(for: now)
            case .week:  return cal.date(byAdding: .day, value: -7, to: now)
            case .all:   return nil
            }
        }
    }

    private var filteredEntries: [LoggedUtterance] {
        guard let earliest = filter.earliest() else { return allEntries }
        return allEntries.filter { $0.createdAt >= earliest }
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    /// Top 3 most-frequent tile combinations in the current filter window.
    /// Combos are ordered by tile keys for stable grouping (matches cache-key semantics).
    private var topCombos: [(keys: [String], count: Int, latestSentence: String)] {
        var buckets: [String: (keys: [String], count: Int, latest: LoggedUtterance)] = [:]
        for entry in filteredEntries {
            let sortedKeys = entry.tileKeys.sorted()
            let bucketKey = sortedKeys.joined(separator: "+")
            if let existing = buckets[bucketKey] {
                let latest = entry.createdAt > existing.latest.createdAt ? entry : existing.latest
                buckets[bucketKey] = (existing.keys, existing.count + 1, latest)
            } else {
                buckets[bucketKey] = (sortedKeys, 1, entry)
            }
        }
        return buckets.values
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { ($0.keys, $0.count, $0.latest.sentence) }
    }

    private var groupedByDay: [(day: Date, entries: [LoggedUtterance])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { cal.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day] ?? [])
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Time Range", selection: $filter) {
                    ForEach(TimeFilter.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if filteredEntries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No utterances yet",
                        systemImage: "text.bubble",
                        description: Text("Finalized sentence tray groups will appear here for review.")
                    )
                }
            } else {
                Section("Summary") {
                    LabeledContent("Utterances", value: "\(filteredEntries.count)")
                    if !topCombos.isEmpty {
                        ForEach(Array(topCombos.enumerated()), id: \.offset) { index, combo in
                            comboRow(rank: index + 1, combo: combo)
                        }
                    }
                }

                ForEach(groupedByDay, id: \.day) { group in
                    Section(dayHeader(for: group.day)) {
                        ForEach(group.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func entryRow(_ entry: LoggedUtterance) -> some View {
        HStack(spacing: 10) {
            TileGridIcon(tiles: tileSelections(for: entry.tileKeys))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.sentence.isEmpty ? "(no sentence)" : entry.sentence)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let scene = entry.sceneName, !scene.isEmpty {
                        Text("• \(scene)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if entry.repetitionCount > 0 {
                Label("\(entry.repetitionCount)", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.18))
                    )
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func comboRow(rank: Int, combo: (keys: [String], count: Int, latestSentence: String)) -> some View {
        HStack(spacing: 10) {
            Text("#\(rank)")
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(.secondary)
                .frame(width: 22)
            TileGridIcon(tiles: tileSelections(for: combo.keys))
            VStack(alignment: .leading, spacing: 2) {
                Text(combo.latestSentence.isEmpty ? combo.keys.joined(separator: " + ") : combo.latestSentence)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(combo.count)×")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func tileSelections(for keys: [String]) -> [TileSelection] {
        keys.compactMap { key in
            guard let tile = tileLookup[key] else { return nil }
            return TileSelection(from: tile)
        }
    }

    private func dayHeader(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

#Preview {
    NavigationStack {
        ActivityLogView()
    }
    .previewEnvironment()
}
