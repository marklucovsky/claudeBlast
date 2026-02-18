//
//  BlasterScene.swift
//  claudeBlast
//

import SwiftData
import Foundation

@Model
final class BlasterScene {
    var id: String = UUID().uuidString
    var name: String = ""
    var descriptionText: String = ""
    var isActive: Bool = false
    var created: Date = Date.now

    init(name: String, descriptionText: String = "", isActive: Bool = false) {
        self.name = name
        self.descriptionText = descriptionText
        self.isActive = isActive
    }
}
