// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageTileModel.swift
//  claudeBlast
//

import SwiftData
import Foundation

@Model
final class PageTileModel: Identifiable {
    var id: String = UUID().uuidString
    @Relationship(deleteRule: .nullify) var tile: TileModel
    var link: String = ""
    var isAudible: Bool = true

    init(tile: TileModel, link: String = "", isAudible: Bool = true) {
        self.tile = tile
        self.link = link
        self.isAudible = isAudible
    }
}
