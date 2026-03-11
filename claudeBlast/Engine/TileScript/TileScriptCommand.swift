// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptCommand.swift
//  claudeBlast
//

import Foundation

/// A single action within a tile row: either navigate to a page or tap a tile.
enum TileAction: Sendable {
    case navigate(pageKey: String)
    case tap(tileKey: String)
}

/// Parsed tile row: a sequence of actions that form one utterance.
struct TileRow: Sendable {
    let actions: [TileAction]
    /// The original text from the YAML (e.g. "<home>, mom, <food>, pizza")
    let rawText: String
    /// Trailing `# comment` from the YAML line, if any.
    let comment: String?

    /// The individual text tokens for display (e.g. ["<home>", "mom", "<food>", "pizza"]).
    var tokens: [String] {
        actions.map { action in
            switch action {
            case .navigate(let key): return "<\(key)>"
            case .tap(let key): return key
            }
        }
    }
}

/// Bulk tile generation spec.
struct BulkTileSpec: Sendable {
    let count: Int
    let source: BulkSource
    let minLength: Int
    let maxLength: Int

    enum BulkSource: String, Sendable {
        case mostCommon = "most-common"
        case random
        case allCombos = "all-combos"
    }
}

/// Timing value: either a named preset or an explicit duration.
enum TimingValue: Sendable, Equatable {
    case human
    case fast
    case instant
    case explicit(milliseconds: Int)

    var duration: Duration {
        switch self {
        case .human: return .milliseconds(800)
        case .fast: return .milliseconds(100)
        case .instant: return .zero
        case .explicit(let ms): return .milliseconds(ms)
        }
    }
}

/// A single command in a TileScript.
enum TileScriptCommand: Sendable {
    case tiles(rows: [TileRow])
    case bulkTiles(spec: BulkTileSpec)
    case clear
    case comment(text: String)
    case wait(duration: Duration)
    case setAudio(enabled: Bool)
    case setTileWait(value: TimingValue)
    case setSentenceWait(value: TimingValue)
    case setProvider(name: String)
    case setScene(name: String)
}
