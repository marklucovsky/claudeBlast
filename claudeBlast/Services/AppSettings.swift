// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AppSettings.swift
//  claudeBlast
//

import SwiftData
import Foundation

enum AppSettingsKey {
    static let bootstrapVersion  = "bootstrap_version"
    static let icloudEnabled     = "icloud_enabled"
    static let openaiApiKey      = "openai_api_key"
    static let providerChoice    = "provider_choice"
    static let audioEnabled          = "audio_enabled"
    static let tileSpeechEnabled     = "tile_speech_enabled"
    static let speechVoiceIdentifier = "speech_voice_identifier"
    static let tileMinSize           = "tile_min_size"
    static let compareProviders      = "compare_providers"
    static let devShowNav            = "dev_show_nav"
    static let imageSet              = "image_set"
}

/// Version stamp written to UserDefaults after bootstrap completes.
/// Primary purpose: first-launch detection.
/// Bump only if a structural change requires forcing a full re-bootstrap from the bundle.
let currentBootstrapVersion: Int = 1

func setModelContainer(icloudEnabled: Bool) -> ModelContainer {
    let schema = Schema([
        TileModel.self, PageModel.self, PageTileModel.self,
        SentenceCache.self, BlasterScene.self, MetricEvent.self,
        RecordedScript.self,
    ])
    let localConfig = ModelConfiguration(schema: schema,
                                         isStoredInMemoryOnly: false,
                                         cloudKitDatabase: .none)
    let cloudKitConfig = ModelConfiguration(schema: schema,
                                            isStoredInMemoryOnly: false,
                                            cloudKitDatabase: .automatic)
    // iCloud defaults OFF. Toggle available on debug builds so CloudKit sync
    // can be tested on real devices without a special build. try? falls back
    // gracefully if the CloudKit entitlement is absent.
    if icloudEnabled,
       let container = try? ModelContainer(for: schema, configurations: [cloudKitConfig]) {
        return container
    }
    do {
        return try ModelContainer(for: schema, configurations: [localConfig])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}
