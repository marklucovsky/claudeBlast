// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CodableTypes.swift
//  claudeBlast
//
//  Lightweight Codable struct for decoding vocabulary.json. Scene/page
//  decoding lives in SceneJSON.swift now that pages are inline.
//

import Foundation

struct TileModelCodable: Codable {
    let key: String
    let wordClass: String
}
