// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScript.swift
//  claudeBlast
//

import Foundation

/// A parsed TileScript: metadata, global settings, and a list of commands.
struct TileScript: Sendable {
    let name: String
    let description: String
    let audio: Bool
    let tileWait: TimingValue
    let sentenceWait: TimingValue
    let provider: String?
    let scene: String?
    let commands: [TileScriptCommand]
}
