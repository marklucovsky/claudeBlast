//
//  SentenceResult.swift
//  claudeBlast
//

import Foundation

struct TileSelection: Sendable, Equatable, Hashable {
    let key: String
    let value: String
    let wordClass: String

    init(key: String, value: String, wordClass: String) {
        self.key = key
        self.value = value
        self.wordClass = wordClass
    }

    init(from tile: TileModel) {
        self.key = tile.key
        self.value = tile.value
        self.wordClass = tile.wordClass
    }
}

struct SentenceResult: Sendable {
    let text: String
    let audioData: Data?
    let audioFormat: String?

    init(text: String, audioData: Data? = nil, audioFormat: String? = nil) {
        self.text = text
        self.audioData = audioData
        self.audioFormat = audioFormat
    }
}
