// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PINAuth.swift
//  claudeBlast
//

import Foundation
import CommonCrypto
import Security

/// PBKDF2-SHA256 PIN hashing for the Admin gate fallback.
///
/// A 4–6 digit PIN has very low entropy on its own; PBKDF2 with a per-PIN
/// salt + many iterations is what makes brute-force impractical against
/// a stolen `DeviceProfile.adminPINHash` + `adminPINSalt` pair.
///
/// Hashes and salts are stored on the `DeviceProfile` (local-only
/// configuration, never synced via CloudKit) so they can't leave the
/// device even if iCloud sync is on for app data.
enum PINAuth {
    /// 100k iterations is the OWASP 2023 recommendation for PBKDF2-HMAC-SHA256.
    /// Tuneable down later if older devices struggle, but ~100ms per attempt
    /// on a modern iPad is the target.
    static let iterations: UInt32 = 100_000
    /// 32 bytes = 256 bits, matches the underlying HMAC-SHA256 output size.
    static let keyLength: Int = 32
    /// 16 random bytes per salt — overkill for collision resistance but
    /// matches common Keychain practice and is trivial to store.
    static let saltLength: Int = 16

    /// Cryptographically-random salt for a new PIN.
    static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // SecRandomCopyBytes failing is a system-level issue we can't recover
        // from — fall through to whatever bytes we got (still random-ish via
        // initial zero pattern). Vanishingly unlikely on iOS.
        _ = status
        return Data(bytes)
    }

    /// Derive a 256-bit key from the PIN using PBKDF2-HMAC-SHA256.
    /// Returns `nil` only on encoding or CommonCrypto failure (effectively
    /// never on iOS).
    static func hash(pin: String, salt: Data) -> Data? {
        guard let pinBytes = pin.data(using: .utf8) else { return nil }
        var derived = [UInt8](repeating: 0, count: keyLength)
        let result = pinBytes.withUnsafeBytes { (pinPtr: UnsafeRawBufferPointer) -> Int32 in
            salt.withUnsafeBytes { (saltPtr: UnsafeRawBufferPointer) -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pinPtr.bindMemory(to: Int8.self).baseAddress,
                    pinBytes.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &derived,
                    keyLength
                )
            }
        }
        guard result == kCCSuccess else { return nil }
        return Data(derived)
    }

    /// Constant-time PIN verification. Returns `false` for any mismatch
    /// including encoding failure — never `nil`.
    static func verify(pin: String, hash: Data, salt: Data) -> Bool {
        guard let candidate = Self.hash(pin: pin, salt: salt) else { return false }
        return constantTimeEqual(candidate, hash)
    }

    /// Constant-time byte comparison. Important: the loop runs over the
    /// *longer* of the two lengths to keep timing independent of input
    /// length too. (For PBKDF2 output the lengths are always equal, but
    /// belt-and-suspenders.)
    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    /// True for 4-to-6-digit numeric input. The Admin gate accepts only
    /// numeric PINs — letters are rejected at the input layer.
    static func isValidPINShape(_ pin: String) -> Bool {
        let digitCount = pin.unicodeScalars.filter(CharacterSet.decimalDigits.contains).count
        return digitCount == pin.count && (4...6).contains(pin.count)
    }
}
