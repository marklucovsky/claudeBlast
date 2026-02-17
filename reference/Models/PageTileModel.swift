//
//  PageTileModel.swift
//  blaster
//
//  Created by MARK LUCOVSKY on 5/12/25.
//

import SwiftData
import SwiftUI
import Foundation

@Model
final class PageTileModel: Identifiable {
  var id: String = UUID().uuidString
  @Relationship(deleteRule: .nullify) var tile: TileModel
  var link: String = ""
  var isAudible: Bool = true
  
  init(tile: TileModel, link: String, isAudible: Bool) {
    self.tile = tile
    self.link = link
    self.isAudible = isAudible
  }
  
  convenience init(tile: TileModel) {
    self.init(tile:tile, link: "", isAudible: true)
  }
}

