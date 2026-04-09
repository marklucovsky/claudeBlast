// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
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
    var homePageKey: String = "home"
    var isDefault: Bool = false
    var isActive: Bool = false
    var isImported: Bool = false
    var created: Date = Date.now
    var lastModified: Date = Date.now
    /// Source URL if the scene was imported from a web link.
    var sourceURL: String = ""

    @Relationship(deleteRule: .nullify) var pages: [PageModel] = []

    init(name: String, descriptionText: String = "", homePageKey: String = "home",
         isDefault: Bool = false, isActive: Bool = false) {
        self.name = name
        self.descriptionText = descriptionText
        self.homePageKey = homePageKey
        self.isDefault = isDefault
        self.isActive = isActive
    }

    /// Activate this scene, deactivating any other active scene in the context.
    func activate(context: ModelContext) throws {
        let allScenes = try context.fetch(FetchDescriptor<BlasterScene>())
        for scene in allScenes where scene.isActive {
            scene.isActive = false
        }
        self.isActive = true
    }

    /// Deactivate this scene and restore the default scene.
    func deactivateAndRestoreDefault(context: ModelContext) throws {
        self.isActive = false
        let defaultScenes = try context.fetch(
            FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.isDefault })
        )
        if let defaultScene = defaultScenes.first {
            defaultScene.isActive = true
        }
    }
}
