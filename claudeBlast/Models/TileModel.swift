//
//  TileModel.swift
//  claudeBlast
//

import SwiftData
import SwiftUI
import Foundation

enum TileType: String, Codable {
    case word
    case phrase
}

@Model
final class TileModel: Identifiable {
    var id: String = UUID().uuidString
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
    }

    convenience init(from codable: TileModelCodable) {
        self.init(key: codable.key, wordClass: codable.wordClass)
    }
}
