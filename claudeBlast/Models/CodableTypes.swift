//
//  CodableTypes.swift
//  claudeBlast
//
//  Lightweight Codable structs for decoding vocabulary.json and pages.json.
//

import Foundation

struct TileModelCodable: Codable {
    let key: String
    let wordClass: String
}

struct PageTileCodable: Codable {
    let key: String
    let link: String
    let isAudible: Bool
}

struct PageModelCodable: Codable {
    let key: String
    let pageTiles: [PageTileCodable]
}
