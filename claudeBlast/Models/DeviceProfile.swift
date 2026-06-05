// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  DeviceProfile.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Per-device identity + posture. Never synced — each device has its own.
/// Backed by a separate ModelConfiguration with `cloudKitDatabase: .none`
/// so a therapist's iPad and their iPhone can have different roles even
/// when ChildProfile data syncs between them.
@Model
final class DeviceProfile {
    var id: String = UUID().uuidString
    /// `DeviceRole.rawValue`. Stored as String for SwiftData/CloudKit compat
    /// even though this entity is local-only — keeps modeling consistent.
    var roleRaw: String = DeviceRole.personal.rawValue
    var displayName: String = ""
    /// Patient devices: always true (forced at onboarding). Therapist devices:
    /// optional toggle. Personal devices: always false.
    var requireFaceIDForAdmin: Bool = false
    /// PBKDF2-hashed PIN used as Face ID fallback. nil = no PIN set yet.
    /// Wired in commit 6; declared here so the schema is stable.
    var adminPINHash: Data?
    var adminPINSalt: Data?
    var onboardingCompleted: Bool = false
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    var role: DeviceRole {
        get { DeviceRole(rawValue: roleRaw) ?? .personal }
        set { roleRaw = newValue.rawValue; modifiedAt = .now }
    }

    init(role: DeviceRole = .personal, displayName: String = "",
         requireFaceIDForAdmin: Bool = false, onboardingCompleted: Bool = false) {
        self.roleRaw = role.rawValue
        self.displayName = displayName
        self.requireFaceIDForAdmin = requireFaceIDForAdmin
        self.onboardingCompleted = onboardingCompleted
    }
}

enum DeviceRole: String, CaseIterable, Codable {
    case patient
    case therapist
    case personal

    var displayName: String {
        switch self {
        case .patient:   return "Patient"
        case .therapist: return "Therapist"
        case .personal:  return "Personal"
        }
    }

    var summary: String {
        switch self {
        case .patient:
            return "This device belongs to one child. Admin is locked behind Face ID; parents get a safe-subset settings sheet."
        case .therapist:
            return "This device manages a roster of patients. Admin is open by default; Face ID is opt-in."
        case .personal:
            return "Your own device for demos, testing, and tuning. No child profile, no auth gate."
        }
    }
}
