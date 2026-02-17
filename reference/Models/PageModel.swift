//
//  PageModel.swift
//  blaster
//
//  Created by MARK LUCOVSKY on 2/24/25.
//

import SwiftData
import Foundation

@Model
final class PageModel: Identifiable {
  var id: String = UUID().uuidString
  //var metrics: [MetricType: Metric]
  var created: Date = Date.now
  
  // display properties
  var displayName: String = ""
  
  var tileOrder: [String] = []
  @Relationship(deleteRule: .cascade) var tiles: [PageTileModel] = []
  
  init(displayName: String, tileOrder: [String]) {
    self.displayName = displayName
    self.tileOrder = tileOrder
  }
  
  /// Computed property to return ordered tiles
  var orderedTiles: [PageTileModel] {
    tileOrder.compactMap { id in tiles.first { $0.id == id } }
  }
  
  /// Function to reorder tiles
  func updateTileOrder(with newOrder: [String]) {
    tileOrder = newOrder.filter { id in tiles.contains { $0.id == id } }
  }
  
  //func addTile(_ tile: TileModel) {
  //    tiles.append(tile)
  //    tileOrder.append(tile.id)
  //}
  
  func removeTile(_ tile: PageTileModel) {
      tiles.removeAll { $0.id == tile.id }
      tileOrder.removeAll { $0 == tile.id }
  }
  
  func moveTile(from sourceIndex: Int, to destinationIndex: Int) {
      let movedTile = tileOrder.remove(at: sourceIndex)
      tileOrder.insert(movedTile, at: destinationIndex)
  }
  
  
}

extension PageModel {
    static func make(displayName: String, tiles: [PageTileModel], tileOrder: [String]) -> PageModel {
        let page = PageModel(displayName: displayName, tileOrder: tileOrder)
        // This should be allowed here since you're in the same file:
        page.tiles = tiles // This avoids calling it in the actual `init`
        return page
    }
}
  
