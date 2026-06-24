// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  EvalReport.swift
//  claudeBlastTests
//
//  Aggregation + serialization for an eval run. This is the run-over-run
//  comparison substrate — a small JSON artifact ("baseline") capturing the
//  scores, not the rich human-review report (deferred; likely converges with
//  usage-log reporting later). Pure value types + a writer, so the rollup math
//  is unit-tested offline without any network.

import Foundation

// MARK: - Per-case results

struct SentenceCaseResult: Codable {
    let id: String
    let output: String
    let tier1Passed: Bool
    let tier1Issues: [String]
    /// Nil when the judge wasn't run (Tier-1-only pass).
    var judge: SentenceVerdict?
}

struct EscalationCaseResult: Codable {
    let id: String
    let ladder: [String]
    let intensities: [Int]
    let tier1Passed: Bool
    let tier1Issues: [String]
    var judge: EscalationVerdict?
}

// MARK: - Run report

struct EvalReport: Codable {
    var subjectModel: String
    var judgeModel: String?
    /// ISO-8601 timestamp, injected by the caller (Date() is unavailable in some
    /// contexts; tests pass it explicitly).
    var timestamp: String
    var sentences: [SentenceCaseResult]
    var escalations: [EscalationCaseResult]

    // MARK: Rollups

    /// Mean of the judge's per-sentence mean scores (nil if no judge ran).
    var sentenceMeanScore: Double? {
        let means = sentences.compactMap { $0.judge?.mean }
        guard !means.isEmpty else { return nil }
        return means.reduce(0, +) / Double(means.count)
    }

    /// Fraction of sentence cases passing the Tier-1 floor.
    var sentenceTier1PassRate: Double {
        guard !sentences.isEmpty else { return 1 }
        return Double(sentences.filter(\.tier1Passed).count) / Double(sentences.count)
    }

    /// Across all escalation ladders: fraction of adjacent steps the judge
    /// called "escalates". The headline escalation-quality number.
    var escalationStepEscalateRate: Double? {
        let calls = escalations.compactMap(\.judge).flatMap(\.calls)
        guard !calls.isEmpty else { return nil }
        return Double(calls.filter { $0 == .escalates }.count) / Double(calls.count)
    }

    /// Total judge-detected regressions across ladders (lower is better).
    var escalationRegressions: Int {
        escalations.compactMap(\.judge).map(\.regressesCount).reduce(0, +)
    }

    /// Fraction of escalation ladders passing the Tier-1 floor (monotonic, no
    /// degenerate rungs).
    var escalationTier1PassRate: Double {
        guard !escalations.isEmpty else { return 1 }
        return Double(escalations.filter(\.tier1Passed).count) / Double(escalations.count)
    }

    /// One-line human summary for the test log.
    var summaryLine: String {
        func pct(_ x: Double?) -> String { x.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a" }
        func sc(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "n/a" }
        return """
        subject=\(subjectModel) judge=\(judgeModel ?? "none") | \
        sentence: tier1 \(pct(sentenceTier1PassRate)) judge \(sc(sentenceMeanScore))/5 | \
        escalation: tier1 \(pct(escalationTier1PassRate)) escalate-rate \(pct(escalationStepEscalateRate)) regressions \(escalationRegressions)
        """
    }
}

// MARK: - Writer

enum EvalReportWriter {
    /// Serialize a report to pretty JSON.
    static func json(_ report: EvalReport) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(report)
    }

    /// Write the report under a stable directory so successive runs are easy to
    /// diff. Returns the file URL. Caller supplies a filename stem (e.g. a
    /// timestamp) since Date() isn't available here.
    @discardableResult
    static func write(_ report: EvalReport, stem: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("blaster-eval", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("eval-\(stem).json")
        try json(report).write(to: url)
        return url
    }
}
