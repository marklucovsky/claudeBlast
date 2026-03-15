// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptParser.swift
//  claudeBlast
//

import Foundation
import Yams

/// Parses YAML text into a TileScript model.
struct TileScriptParser {

    enum ParseError: LocalizedError {
        case invalidYAML(String)
        case missingField(String)
        case invalidCommand(String)

        var errorDescription: String? {
            switch self {
            case .invalidYAML(let msg): return "Invalid YAML: \(msg)"
            case .missingField(let field): return "Missing required field: \(field)"
            case .invalidCommand(let msg): return "Invalid command: \(msg)"
            }
        }
    }

    /// Parse a YAML string into a TileScript.
    static func parse(_ yaml: String) throws -> TileScript {
        // Pre-extract line comments from tile row lines before Yams strips them.
        let lineComments = extractLineComments(from: yaml)

        guard let root = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw ParseError.invalidYAML("Root must be a YAML mapping")
        }

        let name = root["name"] as? String ?? "Untitled"
        let description = root["description"] as? String ?? ""
        let audio = parseAudioValue(root["audio"]) ?? true
        let tileWait = parseTimingValue(root["tileWait"]) ?? .human
        let sentenceWait = parseTimingValue(root["sentenceWait"]) ?? .human
        let provider = root["provider"] as? String
        let scene = root["scene"] as? String

        guard let scriptArray = root["script"] as? [[String: Any]] else {
            throw ParseError.missingField("script")
        }

        let commands = try scriptArray.flatMap { try parseCommand($0, lineComments: lineComments) }

        return TileScript(
            name: name,
            description: description,
            audio: audio,
            tileWait: tileWait,
            sentenceWait: sentenceWait,
            provider: provider,
            scene: scene,
            commands: commands
        )
    }

    // MARK: - Line Comment Extraction

    /// Scan raw YAML lines for trailing `# comment` on tile row entries.
    /// Returns a dictionary mapping the stripped tile content → comment text.
    /// e.g. "<home>, mom, <food>, pizza" → "requesting pizza from mom"
    private static func extractLineComments(from yaml: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match YAML list items: "- <content>  # comment"
            guard trimmed.hasPrefix("- ") else { continue }
            let afterDash = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // Skip structured entries (tiles:, comment:, etc.)
            if afterDash.contains(":") && !afterDash.hasPrefix("<") { continue }

            // Find trailing comment: look for ` #` or `  #` (space before hash)
            // but not inside angle brackets
            if let commentRange = findTrailingComment(in: afterDash) {
                let content = String(afterDash[afterDash.startIndex..<commentRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let comment = String(afterDash[commentRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !comment.isEmpty {
                    result[content] = comment
                }
            }
        }
        return result
    }

    /// Find the range of ` #` that starts a trailing comment (not inside the value).
    private static func findTrailingComment(in str: String) -> Range<String.Index>? {
        // Search for " #" pattern — the space before # distinguishes comment from content
        var searchStart = str.startIndex
        while let range = str.range(of: " #", range: searchStart..<str.endIndex) {
            // Make sure this isn't inside angle brackets
            let prefix = str[str.startIndex..<range.lowerBound]
            let openCount = prefix.filter({ $0 == "<" }).count
            let closeCount = prefix.filter({ $0 == ">" }).count
            if openCount == closeCount {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    // MARK: - Command Parsing

    private static func parseCommand(_ dict: [String: Any], lineComments: [String: String]) throws -> [TileScriptCommand] {
        if let tilesValue = dict["tiles"] {
            return try [parseTilesCommand(tilesValue, lineComments: lineComments)]
        }
        if let comment = dict["comment"] as? String {
            return [.comment(text: comment)]
        }
        if let waitValue = dict["wait"] {
            let duration = parseDurationString(waitValue)
            return [.wait(duration: duration)]
        }
        if dict["clear"] != nil {
            return [.clear]
        }
        if let audioValue = dict["audio"] {
            if let enabled = parseAudioValue(audioValue) {
                return [.setAudio(enabled: enabled)]
            }
        }
        if let twValue = dict["tileWait"] {
            if let tv = parseTimingValue(twValue) {
                return [.setTileWait(value: tv)]
            }
        }
        if let swValue = dict["sentenceWait"] {
            if let tv = parseTimingValue(swValue) {
                return [.setSentenceWait(value: tv)]
            }
        }
        if let providerName = dict["provider"] as? String {
            return [.setProvider(name: providerName)]
        }
        if let sceneName = dict["scene"] as? String {
            return [.setScene(name: sceneName)]
        }

        throw ParseError.invalidCommand("Unrecognized command: \(dict.keys.joined(separator: ", "))")
    }

    private static func parseTilesCommand(_ value: Any, lineComments: [String: String]) throws -> TileScriptCommand {
        // Bulk spec: {count: N, source: ..., length: "2-4"}
        if let dict = value as? [String: Any], dict["count"] != nil {
            let count = dict["count"] as? Int ?? 100
            let sourceStr = dict["source"] as? String ?? "random"
            let source = BulkTileSpec.BulkSource(rawValue: sourceStr) ?? .random
            let lengthStr = dict["length"] as? String ?? "2-4"
            let (minLen, maxLen) = parseLengthRange(lengthStr)
            return .bulkTiles(spec: BulkTileSpec(count: count, source: source, minLength: minLen, maxLength: maxLen))
        }

        // Row array: list of strings
        if let rows = value as? [String] {
            let tileRows = rows.map { parseTileRow($0, lineComments: lineComments) }
            return .tiles(rows: tileRows)
        }

        // Single string
        if let single = value as? String {
            return .tiles(rows: [parseTileRow(single, lineComments: lineComments)])
        }

        throw ParseError.invalidCommand("tiles value must be a list of strings or a bulk spec")
    }

    /// Parse a single tile row string like "<home>, mom, <food>, pizza"
    static func parseTileRow(_ row: String, lineComments: [String: String] = [:]) -> TileRow {
        let rawText = row.trimmingCharacters(in: .whitespaces)
        let comment = lineComments[rawText]

        let parts = rawText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let actions: [TileAction] = parts.compactMap { part in
            guard !part.isEmpty else { return nil }
            if part.hasPrefix("<") && part.hasSuffix(">") {
                let pageKey = String(part.dropFirst().dropLast())
                return .navigate(pageKey: pageKey)
            }
            return .tap(tileKey: part)
        }
        return TileRow(actions: actions, rawText: rawText, comment: comment)
    }

    // MARK: - Value Parsing

    private static func parseAudioValue(_ value: Any?) -> Bool? {
        if let str = value as? String {
            return str.lowercased() == "on" || str.lowercased() == "true"
        }
        if let bool = value as? Bool { return bool }
        return nil
    }

    static func parseTimingValue(_ value: Any?) -> TimingValue? {
        guard let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case ".human", "human": return .human
        case ".fast", "fast": return .fast
        case ".instant", "instant": return .instant
        default:
            if let ms = parseDurationToMs(trimmed) {
                return .explicit(milliseconds: ms)
            }
            return nil
        }
    }

    private static func parseDurationToMs(_ str: String) -> Int? {
        if str.hasSuffix("ms"), let val = Int(str.dropLast(2)) {
            return val
        }
        if str.hasSuffix("s"), let val = Double(str.dropLast(1)) {
            return Int(val * 1000)
        }
        return nil
    }

    private static func parseDurationString(_ value: Any) -> Duration {
        if let str = value as? String {
            if let ms = parseDurationToMs(str) {
                return .milliseconds(ms)
            }
        }
        if let secs = value as? Int {
            return .seconds(secs)
        }
        if let secs = value as? Double {
            return .milliseconds(Int(secs * 1000))
        }
        return .seconds(1)
    }

    private static func parseLengthRange(_ str: String) -> (Int, Int) {
        let parts = str.split(separator: "-")
        if parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]) {
            return (lo, hi)
        }
        if let single = Int(str) {
            return (single, single)
        }
        return (2, 4)
    }
}
