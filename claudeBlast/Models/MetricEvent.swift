// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MetricEvent.swift
//  claudeBlast
//

import SwiftData
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

@Model
final class MetricEvent {
    var id: String = UUID().uuidString
    var subjectType: String = ""
    var subjectKey: String = ""
    var eventType: MetricType = MetricType.selected
    var timestamp: Date = Date.now

    init(subjectType: String, subjectKey: String, eventType: MetricType) {
        self.subjectType = subjectType
        self.subjectKey = subjectKey
        self.eventType = eventType
    }
}
