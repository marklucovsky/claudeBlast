// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIKeyVault.swift
//  claudeBlast
//

import Foundation

/// Typed accessor for the OpenAI API key.
///
/// Resolution order at read time:
/// 1. `OPENAI_API_KEY` environment variable (developer override; not surfaced
///    in the consumer UI).
/// 2. Keychain entry under `service = com.lucovsky.claudeBlast.api`,
///    `account = openai`.
///
/// Key writes go to the Keychain only — never UserDefaults. On first run
/// after upgrading, `migrateFromUserDefaultsIfNeeded` copies any prior
/// `AppSettingsKey.openaiApiKey` UserDefaults value across once and clears
/// the UserDefaults entry, so the key stops sitting in plist-readable
/// storage even if the user never opens Admin again.
enum OpenAIKeyVault {
    static let service = "com.lucovsky.claudeBlast.api"
    static let account = "openai"

    static func defaultStore() -> SecretStore {
        KeychainSecretStore(service: service, account: account)
    }

    /// The effective key right now. Returns `nil` (not an empty string) when
    /// no key is available, so callers can branch on `if let`.
    static func currentKey(
        env: ProcessInfo = .processInfo,
        store: SecretStore = defaultStore()
    ) -> String? {
        if let envKey = env.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespaces),
           !envKey.isEmpty {
            return envKey
        }
        guard let stored = store.read(), !stored.isEmpty else { return nil }
        return stored
    }

    /// Persist a new key. Empty/whitespace-only input deletes the entry —
    /// matches the "clear it from Admin" affordance.
    @discardableResult
    static func setKey(_ key: String, store: SecretStore = defaultStore()) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return store.delete()
        }
        return store.write(trimmed)
    }

    /// Drop the persisted key. Env var still wins at the next read.
    @discardableResult
    static func clearKey(store: SecretStore = defaultStore()) -> Bool {
        store.delete()
    }

    /// One-shot migration. Idempotent.
    ///
    /// Behavior:
    /// - If Keychain already has a non-empty value, ensure the legacy
    ///   UserDefaults entry is cleared and return `false`.
    /// - If Keychain is empty and UserDefaults has a non-empty value, copy
    ///   it to Keychain, clear UserDefaults, and return `true`.
    /// - Otherwise return `false`.
    @discardableResult
    static func migrateFromUserDefaultsIfNeeded(
        store: SecretStore = defaultStore(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let existing = store.read(), !existing.isEmpty {
            if defaults.string(forKey: AppSettingsKey.openaiApiKey) != nil {
                defaults.removeObject(forKey: AppSettingsKey.openaiApiKey)
            }
            return false
        }
        guard let legacy = defaults.string(forKey: AppSettingsKey.openaiApiKey),
              !legacy.isEmpty else {
            return false
        }
        let ok = store.write(legacy)
        if ok {
            defaults.removeObject(forKey: AppSettingsKey.openaiApiKey)
        }
        return ok
    }
}
