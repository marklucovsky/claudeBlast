//
//  TileModel.swift
//  blaster
//
//  Created by MARK LUCOVSKY on 1/17/25.
//

import SwiftData
import SwiftUI
import Foundation

// enums
// accounting
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

enum TilePage: String, Codable {
  case all
  case home
  case play
  case eat
  case watch
  case mostused
  case people
  case social
  case questions
  case places
  case groups
  case drinks
  case snacks
  case meals
  case fruit
  case veggie
  case shape
}

@Model
final class TileModel: Identifiable {
  
  // state
  var id: String = UUID().uuidString
  var metrics: [MetricType: Metric]
  var created: Date = Date.now
  
  // display properties
  var displayName: String = ""
  var bundleImage: String = ""
  var userImageData: Data?  // 🔹 Stores user-selected image
  
  
  // value properties
  var value: String = ""
  var type: TileType = TileType.word
  var key: String = ""
  var pages: Set<String> = []
  var wordClass: String = ""
  
  // ✅ Convenience getter to load `UIImage` from `Data`
  var userImage: UIImage? {
    guard let userImageData else { return nil }
    return UIImage(data: userImageData)
  }
  
  convenience init(key: String, wordClass: String) {
    var initValue: String
    var initKey: String
    
    initKey = key
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    
    initValue = initKey
      .lowercased()
      .replacingOccurrences(of: "_", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    
    self.init(key: initKey, value: initValue, wordClass: wordClass)
  }
  
  init(key: String, value: String, wordClass: String) {
    self.displayName = value
    self.value = value
    self.key = key
    
    // todo: check against bundled image bank and use default if there is no image
    self.bundleImage = key
    self.wordClass = wordClass
    self.pages = [wordClass]
   
    
    
    self.metrics = [.selected: Metric(type: .selected),
                    .used: Metric(type: .used),
                    .edited: Metric(type: .edited),
                    .created: Metric(type: .edited),
                    .hit: Metric(type: .edited)
    ]
    self.recordMetric(metric: .edited)
  }
  
  convenience init(from codable: TileModelCodable) {
    self.init(key: codable.key, wordClass: codable.wordClass)
  }
  
  func recordMetric(metric: MetricType) -> TileModel.Metric {
    if self.metrics[metric] == nil {
      self.metrics[metric] = Metric(type: metric)
    }
    self.metrics[metric]!.record()
    return self.metrics[metric]!
  }
  
  func getMetric(metric: MetricType) -> TileModel.Metric? {
    if let metric = self.metrics[metric] {
      return metric
    }
    return nil
  }
  
  func getMetricCount(metric: MetricType) -> Int {
    if let metric = self.metrics[metric] {
      return metric.count
    }
    return 0
  }
  
  // sub types
  // Metric -- used to count and timestamp something like selected, etc.
  struct Metric: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    let type: MetricType
    var count: Int = 0
    var updated: Date = Date.now
    
    // New initializer for converting from MetricCodable
    // -- used for bootstrapping JSON asset data
    init(from codable: MetricCodable) {
      self.type = codable.type
    }
    
    init(type: MetricType) {
      self.type = type
    }
    
    mutating func record() -> TileModel.Metric {
      self.count += 1
      self.updated = Date.now
      return self
    }
  }
  
}

