// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  KeychainStore.swift
//  claudeBlast
//

import Foundation
import Security

/// Minimal abstraction over a service-scoped secret store. The app uses
/// `KeychainSecretStore`; tests inject an in-memory implementation.
protocol SecretStore {
    func read() -> String?
    /// Returns `true` on a successful insert/update.
    @discardableResult
    func write(_ secret: String) -> Bool
    /// Returns `true` if the item was deleted or absent.
    @discardableResult
    func delete() -> Bool
}

/// `kSecClassGenericPassword`-backed secret slot identified by `(service, account)`.
///
/// **Per-device, not synced.** We deliberately omit `kSecAttrSynchronizable`
/// so the OpenAI key never leaves the device — even when CloudKit sync is on
/// for app data. A therapist who provisions multiple devices enters the key
/// once per device.
struct KeychainSecretStore: SecretStore {
    let service: String
    let account: String

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    @discardableResult
    func write(_ secret: String) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }
        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(matchQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var insertQuery = matchQuery
        insertQuery[kSecValueData as String] = data
        // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — readable after
        // first device unlock following a reboot, never leaves this device.
        // Matches the privacy posture documented in PRD.
        insertQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    @discardableResult
    func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Reference-typed in-memory store. Used by tests; convenient for previews.
/// `nonisolated` so the SecretStore conformance is not main-actor-isolated —
/// this matches the protocol's intended use (callable from any context).
nonisolated final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var value: String?

    init(initial: String? = nil) {
        self.value = initial
    }

    func read() -> String? { value }

    @discardableResult
    func write(_ secret: String) -> Bool {
        value = secret
        return true
    }

    @discardableResult
    func delete() -> Bool {
        value = nil
        return true
    }
}
