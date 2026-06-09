// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AppSettings.swift
//  claudeBlast
//

import SwiftData
import Foundation

enum AppSettingsKey {
    /// Legacy: integer version stamp. Pre-Step M bootstrap used this; new code
    /// uses bootstrapContentHash + bootstrapInstalled. Kept declared so the
    /// UserDefaults key isn't accidentally reused.
    static let bootstrapVersion  = "bootstrap_version"
    /// SHA256 hex of the bundled content (vocabulary.json + scenes/*.json) at
    /// the most recent bootstrap. Used in DEBUG builds to auto-re-bootstrap
    /// when a developer edits a bundled file. RELEASE builds ignore this.
    static let bootstrapContentHash = "bootstrap_content_hash"
    /// Set to true the first time bootstrap completes. RELEASE builds use
    /// this as the sole bootstrap gate — once true, app updates never
    /// auto-replace the user's scene/vocab.
    static let bootstrapInstalled   = "bootstrap_installed"
    /// Set once after the one-time tile-provenance backfill runs. Existing
    /// installs predate `TileModel.isSystem`, so their bundled tiles default
    /// to `false`; the backfill marks the ones matching bundled vocabulary as
    /// system. See `BootstrapLoader.backfillTileProvenance`.
    static let tileProvenanceBackfilled = "tile_provenance_backfilled"
    /// Sticky preference for the force-refresh "Save a copy first" toggle.
    /// Default true (safe). Only read when forceRefreshDuplicateRemembered
    /// is true; otherwise the dialog opens with the default each time.
    static let forceRefreshDuplicate           = "force_refresh_duplicate"
    /// Whether the user checked "Remember this choice" in the force-refresh
    /// dialog. False = the dialog re-asks every time with the default
    /// pre-selected. True = the toggle's last value is honored as the
    /// pre-selected value.
    static let forceRefreshDuplicateRemembered = "force_refresh_duplicate_remembered"
    static let icloudEnabled     = "icloud_enabled"
    static let openaiApiKey      = "openai_api_key"
    static let providerChoice    = "provider_choice"
    static let audioEnabled          = "audio_enabled"
    static let tileSpeechEnabled     = "tile_speech_enabled"
    static let speechVoiceIdentifier = "speech_voice_identifier"
    // Deprecated: superseded by `tileSizeStep`. Left declared so the
    // UserDefaults key isn't accidentally reused for an unrelated setting.
    static let tileMinSize           = "tile_min_size"
    static let tileSizeStep          = "tile_size_step"
    static let compareProviders      = "compare_providers"
    static let devShowNav            = "dev_show_nav"
    static let imageSet              = "image_set"

    // Sentence tray timeline settings (PR cb-tray-timeline)
    static let tileCapPerGroup       = "tile_cap_per_group"
    static let idleDebounceMs        = "idle_debounce_ms"
    static let trayBufferSize        = "tray_buffer_size"
    /// Long idle timeout (ms) after which the active group is auto-committed to history (the
    /// equivalent of the Done button firing on its own). 0 disables auto-Done.
    static let autoDoneMs            = "auto_done_ms"
}

// Bootstrap version stamp removed in Step M. needsBootstrap now derives from
// a content hash of the bundled resource files (DEBUG) or the bootstrapInstalled
// flag (RELEASE). See BootstrapLoader.needsBootstrap().

func setModelContainer(icloudEnabled: Bool) -> ModelContainer {
    // Two-config split: DeviceProfile is per-device and must never sync
    // (role differs between an iPad-in-clinic and the therapist's iPhone).
    // Everything else (including ChildProfile, BlasterScene, caches) can
    // sync via CloudKit when opt-in is on.
    //
    // The "synced" configuration keeps the default name/URL so existing
    // installs continue to read the same store file — only the new local
    // configuration gets a distinct on-disk location.
    let syncedSchema = Schema([
        TileModel.self,
        SentenceCache.self, BlasterScene.self, MetricEvent.self,
        RecordedScript.self, LoggedUtterance.self,
        ChildProfile.self,
    ])
    let localSchema = Schema([DeviceProfile.self])
    let allSchema = Schema([
        TileModel.self,
        SentenceCache.self, BlasterScene.self, MetricEvent.self,
        RecordedScript.self, LoggedUtterance.self,
        ChildProfile.self,
        DeviceProfile.self,
    ])

    let localConfig = ModelConfiguration("DeviceLocal",
                                         schema: localSchema,
                                         isStoredInMemoryOnly: false,
                                         cloudKitDatabase: .none)
    let syncedLocalConfig = ModelConfiguration(schema: syncedSchema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .none)
    let syncedCloudConfig = ModelConfiguration(schema: syncedSchema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .automatic)
    // iCloud defaults OFF. Toggle available on debug builds so CloudKit sync
    // can be tested on real devices without a special build. try? falls back
    // gracefully if the CloudKit entitlement is absent.
    if icloudEnabled,
       let container = try? ModelContainer(for: allSchema,
                                           configurations: [localConfig, syncedCloudConfig]) {
        return container
    }
    do {
        return try ModelContainer(for: allSchema,
                                  configurations: [localConfig, syncedLocalConfig])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}
