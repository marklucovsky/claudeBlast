// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
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
