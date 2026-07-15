// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptRunLogger.swift
//  claudeBlast
//

import Foundation
import os

/// Captures a timestamped JSONL event log for a single TileScript run, written to
/// `Documents/TileScriptLogs/` so it can be shared off-device (Files / AirDrop /
/// Messages). Driven by `TileScriptRunner` and gated behind Demo Mode — it's a
/// recording aid for aligning a screen capture, not a normal-run cost.
///
/// Each line is one JSON object:
///   `{"ev":"...","t":<seconds from run start>,"wall":"<ISO8601>", ...}`
/// `t` is elapsed seconds since `run.start`, so a recorded video can be aligned by
/// anchoring a single beat (e.g. the first tile tap) and offsetting everything else.
@MainActor
final class TileScriptRunLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast",
                                       category: "TileScriptRunLog")

    /// Keep only the most recent N run logs on disk.
    private static let maxRetained = 25

    private var startInstant: ContinuousClock.Instant?
    private var lines: [String] = []
    private var scriptName = ""

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Directory / discovery

    /// `Documents/TileScriptLogs/`, created on demand.
    static var logsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("TileScriptLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Existing run-log files, newest first.
    static func existingLogs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension == "jsonl" }
            .sorted { a, b in modDate(a) > modDate(b) }
    }

    static func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: - Lifecycle

    func begin(scriptName: String) {
        self.scriptName = scriptName
        startInstant = .now
        lines = []
        event("run.start", ["script": scriptName])
    }

    /// Append one event. `extra` values must be JSON-encodable primitives / arrays / dicts.
    func event(_ ev: String, _ extra: [String: Any] = [:]) {
        guard let startInstant else { return }
        let elapsed = startInstant.duration(to: .now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        var obj: [String: Any] = [
            "ev": ev,
            "t": (seconds * 1000).rounded() / 1000,   // 1ms precision
            "wall": isoFormatter.string(from: Date()),
        ]
        for (k, v) in extra { obj[k] = v }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            lines.append(line)
        }
    }

    /// Finalize the run: append `run.end`, flush to disk, prune old logs.
    /// Idempotent — a second call after finish/stop is a no-op.
    @discardableResult
    func finish() -> URL? {
        guard startInstant != nil else { return nil }
        event("run.end")
        let url = Self.logsDirectory.appendingPathComponent(fileName())
        let body = lines.joined(separator: "\n") + "\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Self.logger.error("Failed to write run log: \(error.localizedDescription)")
        }
        startInstant = nil
        lines = []
        Self.prune()
        return url
    }

    // MARK: - Helpers

    private func fileName() -> String {
        let slug = scriptName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let safe = slug.isEmpty ? "run" : slug
        return "run-\(safe)-\(fileStampFormatter.string(from: Date())).jsonl"
    }

    private static func prune() {
        let logs = existingLogs()
        guard logs.count > maxRetained else { return }
        for url in logs.dropFirst(maxRetained) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
