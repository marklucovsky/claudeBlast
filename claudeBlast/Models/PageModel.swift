// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageModel.swift
//  claudeBlast
//

import SwiftData
import Foundation

@Model
final class PageModel: Identifiable {
    var id: String = UUID().uuidString
    var created: Date = Date.now
    var displayName: String = ""
    var tileOrder: [String] = []
    @Relationship(deleteRule: .cascade) var tiles: [PageTileModel] = []

    init(displayName: String, tileOrder: [String] = []) {
        self.displayName = displayName
        self.tileOrder = tileOrder
    }

    var orderedTiles: [PageTileModel] {
        tileOrder.compactMap { id in tiles.first { $0.id == id } }
    }

    func removeTile(_ tile: PageTileModel) {
        tiles.removeAll { $0.id == tile.id }
        tileOrder.removeAll { $0 == tile.id }
    }

    func moveTile(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tileOrder.indices.contains(sourceIndex),
              tileOrder.indices.contains(destinationIndex) else { return }
        let moved = tileOrder.remove(at: sourceIndex)
        tileOrder.insert(moved, at: destinationIndex)
    }
}

extension PageModel {
    static func make(displayName: String, tiles: [PageTileModel], tileOrder: [String]) -> PageModel {
        let page = PageModel(displayName: displayName, tileOrder: tileOrder)
        page.tiles = tiles
        return page
    }
}
