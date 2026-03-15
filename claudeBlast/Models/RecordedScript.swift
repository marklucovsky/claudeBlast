// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  RecordedScript.swift
//  claudeBlast
//

import Foundation
import SwiftData

@Model
final class RecordedScript {
    var id: String = UUID().uuidString
    var name: String = ""
    var descriptionText: String = ""
    var yamlContent: String = ""
    var sceneName: String = ""
    var created: Date = Date.now

    init(name: String, descriptionText: String = "", yamlContent: String, sceneName: String) {
        self.id = UUID().uuidString
        self.name = name
        self.descriptionText = descriptionText
        self.yamlContent = yamlContent
        self.sceneName = sceneName
        self.created = .now
    }
}
