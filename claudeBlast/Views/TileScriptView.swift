// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptView.swift
//  claudeBlast
//

import SwiftUI

/// Tab for browsing curated demo scripts and configuring test generation runs.
struct TileScriptView: View {
    @Environment(TileScriptRunner.self) private var runner

    @State private var selectedCount: Int = 1000
    @State private var selectedSource: BulkTileSpec.BulkSource = .mostCommon
    @State private var selectedMinLength: Int = 2
    @State private var selectedMaxLength: Int = 4
    @State private var errorMessage: String?

    private let countOptions = [100, 1_000, 10_000, 200_000, 1_000_000]

    var body: some View {
        NavigationStack {
            List {
                curatedSection
                testGeneratorSection

                if runner.state != .idle {
                    nowPlayingSection
                }
            }
            .navigationTitle("TileScript")
        }
    }

    // MARK: - Curated Demos

    private var curatedSection: some View {
        Section("Curated Demos") {
            ForEach(curatedScripts, id: \.name) { info in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(.body.weight(.medium))
                        Text(info.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Step") {
                        loadAndStep(resourceName: info.resourceName)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(runner.state == .running || runner.state == .paused)
                    Button("Run") {
                        loadAndRun(resourceName: info.resourceName)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(runner.state == .running || runner.state == .paused)
                }
            }
        }
    }

    // MARK: - Test Generator

    private var testGeneratorSection: some View {
        Section("Test Generator") {
            Picker("Entry Count", selection: $selectedCount) {
                ForEach(countOptions, id: \.self) { count in
                    Text(formatCount(count)).tag(count)
                }
            }

            Picker("Source", selection: $selectedSource) {
                Text("Most Common").tag(BulkTileSpec.BulkSource.mostCommon)
                Text("Random").tag(BulkTileSpec.BulkSource.random)
                Text("All Combos").tag(BulkTileSpec.BulkSource.allCombos)
            }

            HStack {
                Text("Tile Length")
                Spacer()
                Stepper("\(selectedMinLength)–\(selectedMaxLength)", value: $selectedMinLength, in: 1...selectedMaxLength)
                Stepper("", value: $selectedMaxLength, in: selectedMinLength...4)
                    .labelsHidden()
            }

            Button("Generate & Run") {
                runBulkGeneration()
            }
            .disabled(runner.state == .running || runner.state == .paused)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        Section("Now Playing") {
            if let script = runner.currentScript {
                Text(script.name)
                    .font(.body.weight(.medium))
            }

            HStack {
                Text("Status")
                Spacer()
                Text(runner.state == .running ? "Running" : runner.state == .paused ? "Paused" : "Finished")
                    .foregroundStyle(.secondary)
            }

            if let progress = runner.bulkProgress {
                ProgressView(value: Double(progress.completed), total: Double(progress.total)) {
                    HStack {
                        Text("\(progress.completed) / \(progress.total)")
                            .font(.caption)
                        if runner.bulkDuplicates > 0 {
                            Text("(\(runner.bulkDuplicates) duplicates skipped)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Text("Command \(runner.commandIndex + 1) / \(runner.totalCommands)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Stop", role: .destructive) {
                runner.stop()
            }
        }
    }

    // MARK: - Actions

    private func loadAndRun(resourceName: String) {
        loadScript(resourceName: resourceName, paused: false)
    }

    private func loadAndStep(resourceName: String) {
        loadScript(resourceName: resourceName, paused: true)
    }

    private func loadScript(resourceName: String, paused: Bool) {
        errorMessage = nil
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "yaml"),
              let yaml = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Could not load script: \(resourceName)"
            return
        }

        do {
            let script = try TileScriptParser.parse(yaml)
            if paused {
                runner.playPaused(script: script)
            } else {
                runner.play(script: script)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runBulkGeneration() {
        errorMessage = nil
        let spec = BulkTileSpec(
            count: selectedCount,
            source: selectedSource,
            minLength: selectedMinLength,
            maxLength: selectedMaxLength
        )
        let script = TileScript(
            name: "Bulk Generation (\(formatCount(selectedCount)))",
            description: "Generating \(formatCount(selectedCount)) cache entries",
            audio: false,
            tileWait: .instant,
            sentenceWait: .instant,
            provider: "mock",
            scene: nil,
            commands: [.bulkTiles(spec: spec)]
        )
        runner.play(script: script)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }

    // MARK: - Curated Script Info

    private struct ScriptInfo {
        let name: String
        let description: String
        let resourceName: String
    }

    private var curatedScripts: [ScriptInfo] {
        [
            ScriptInfo(name: "Basic AAC Demo", description: "Child requesting food from mom", resourceName: "demo_basic"),
            ScriptInfo(name: "Food Ordering", description: "Food ordering scenario with escalation", resourceName: "demo_food"),
        ]
    }
}
