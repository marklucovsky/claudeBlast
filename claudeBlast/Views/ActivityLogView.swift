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

    @State private var filter: Filter = .today

    /// Time-window filters group entries by day (newest first). `mostUsed` flattens entries
    /// into unique tile combinations ordered by frequency across all time.
    enum Filter: String, CaseIterable, Identifiable {
        case today    = "Today"
        case week     = "Past Week"
        case all      = "All Time"
        case mostUsed = "Most Used"
        var id: String { rawValue }

        /// Lower bound (inclusive) for time-based filtering; nil = no bound or non-time mode.
        func earliest(now: Date = .now) -> Date? {
            let cal = Calendar.current
            switch self {
            case .today:    return cal.startOfDay(for: now)
            case .week:     return cal.date(byAdding: .day, value: -7, to: now)
            case .all, .mostUsed: return nil
            }
        }
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private var timeFilteredEntries: [LoggedUtterance] {
        guard let earliest = filter.earliest() else { return allEntries }
        return allEntries.filter { $0.createdAt >= earliest }
    }

    private var groupedByDay: [(day: Date, entries: [LoggedUtterance])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: timeFilteredEntries) { cal.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day] ?? [])
        }
    }

    /// Distinct tile combinations across all entries, ordered by frequency (desc).
    /// Combos are bucketed by sorted-key signature so "eat apple" and "apple eat" merge.
    private var combosByFrequency: [(keys: [String], count: Int, latestSentence: String, latestAt: Date)] {
        var buckets: [String: (keys: [String], count: Int, latest: LoggedUtterance)] = [:]
        for entry in allEntries {
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
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.latest.createdAt > rhs.latest.createdAt
            }
            .map { ($0.keys, $0.count, $0.latest.sentence, $0.latest.createdAt) }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            switch filter {
            case .mostUsed:
                mostUsedContent
            case .today, .week, .all:
                timelineContent
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var timelineContent: some View {
        if timeFilteredEntries.isEmpty {
            emptyState
        } else {
            ForEach(groupedByDay, id: \.day) { group in
                Section(dayHeader(for: group.day)) {
                    ForEach(group.entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mostUsedContent: some View {
        if combosByFrequency.isEmpty {
            emptyState
        } else {
            Section {
                ForEach(Array(combosByFrequency.enumerated()), id: \.offset) { _, combo in
                    comboRow(combo)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Section {
            ContentUnavailableView(
                "No utterances yet",
                systemImage: "text.bubble",
                description: Text("Finalized sentence tray groups will appear here for review.")
            )
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LoggedUtterance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    TileGroupBubble(tiles: tileSelections(for: entry.tileKeys))
                }
                Spacer(minLength: 0)
                if entry.repetitionCount > 0 {
                    escalationBadge(entry.repetitionCount)
                }
            }
            Text(entry.sentence.isEmpty ? "(no sentence)" : entry.sentence)
                .font(.subheadline)
                .lineLimit(3)
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
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func comboRow(_ combo: (keys: [String], count: Int, latestSentence: String, latestAt: Date)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    TileGroupBubble(tiles: tileSelections(for: combo.keys))
                }
                Spacer(minLength: 0)
                Text("\(combo.count)×")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                    .foregroundStyle(.blue)
            }
            if !combo.latestSentence.isEmpty {
                Text(combo.latestSentence)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Text("Last: \(combo.latestAt, format: .relative(presentation: .named))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func escalationBadge(_ count: Int) -> some View {
        Label("\(count)", systemImage: "arrow.triangle.2.circlepath")
            .labelStyle(.titleAndIcon)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.18)))
            .foregroundStyle(.orange)
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
