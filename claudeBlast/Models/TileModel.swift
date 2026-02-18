//
//  TileModel.swift
//  claudeBlast
//

import SwiftData
import SwiftUI
import Foundation

enum MetricType: String, Codable {
    case selected
    case used
    case edited
    case created
    case lookup
    case hit
    case flush
    case refreshed
}

enum TileType: String, Codable {
    case word
    case phrase
}

@Model
final class TileModel: Identifiable {
    var id: String = UUID().uuidString
    var metrics: [MetricType: Metric]
    var created: Date = Date.now

    // Display
    var displayName: String = ""
    var bundleImage: String = ""
    var userImageData: Data?

    // Value
    var value: String = ""
    var type: TileType = TileType.word
    var key: String = ""
    var wordClass: String = ""

    var userImage: UIImage? {
        guard let userImageData else { return nil }
        return UIImage(data: userImageData)
    }

    convenience init(key: String, wordClass: String) {
        let normalizedKey = key
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = normalizedKey
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(key: normalizedKey, value: normalizedValue, wordClass: wordClass)
    }

    init(key: String, value: String, wordClass: String) {
        self.displayName = value
        self.value = value
        self.key = key
        self.bundleImage = key
        self.wordClass = wordClass
        self.metrics = [
            .selected: Metric(type: .selected),
            .used: Metric(type: .used),
            .edited: Metric(type: .edited),
            .created: Metric(type: .created),
            .hit: Metric(type: .hit)
        ]
    }

    convenience init(from codable: TileModelCodable) {
        self.init(key: codable.key, wordClass: codable.wordClass)
    }

    @discardableResult
    func recordMetric(metric: MetricType) -> Metric {
        if metrics[metric] == nil {
            metrics[metric] = Metric(type: metric)
        }
        metrics[metric]!.record()
        return metrics[metric]!
    }

    func getMetricCount(metric: MetricType) -> Int {
        metrics[metric]?.count ?? 0
    }

    struct Metric: Codable, Hashable, Identifiable {
        var id: String = UUID().uuidString
        let type: MetricType
        var count: Int = 0
        var updated: Date = Date.now

        init(type: MetricType) {
            self.type = type
        }

        mutating func record() {
            count += 1
            updated = Date.now
        }
    }
}
