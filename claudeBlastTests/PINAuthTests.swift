// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PINAuthTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

struct PINAuthTests {

    // MARK: - PIN shape validation

    @Test func validShape_acceptsFourToSixDigits() {
        #expect(PINAuth.isValidPINShape("1234"))
        #expect(PINAuth.isValidPINShape("12345"))
        #expect(PINAuth.isValidPINShape("123456"))
    }

    @Test func validShape_rejectsLetters() {
        #expect(!PINAuth.isValidPINShape("12a4"))
        #expect(!PINAuth.isValidPINShape("abcd"))
    }

    @Test func validShape_rejectsWrongLength() {
        #expect(!PINAuth.isValidPINShape("123"))    // too short
        #expect(!PINAuth.isValidPINShape("1234567")) // too long
        #expect(!PINAuth.isValidPINShape(""))       // empty
    }

    // MARK: - Salt + hash

    @Test func newSalt_isSizedCorrectly() {
        let salt = PINAuth.newSalt()
        #expect(salt.count == PINAuth.saltLength)
    }

    @Test func newSalt_yieldsDistinctValues() {
        // 16 random bytes ≠ 16 random bytes with overwhelming probability.
        // Two equal salts would imply a broken SecRandomCopyBytes.
        let salts = (0..<8).map { _ in PINAuth.newSalt() }
        let unique = Set(salts)
        #expect(unique.count == salts.count)
    }

    @Test func hash_producesKeyLengthBytes() {
        let salt = PINAuth.newSalt()
        let h = PINAuth.hash(pin: "1234", salt: salt)
        #expect(h?.count == PINAuth.keyLength)
    }

    @Test func hash_isDeterministicForSameSaltAndPIN() {
        let salt = PINAuth.newSalt()
        let h1 = PINAuth.hash(pin: "654321", salt: salt)
        let h2 = PINAuth.hash(pin: "654321", salt: salt)
        #expect(h1 == h2)
    }

    @Test func hash_differsByPIN() {
        let salt = PINAuth.newSalt()
        let h1 = PINAuth.hash(pin: "1234", salt: salt)
        let h2 = PINAuth.hash(pin: "1235", salt: salt)
        #expect(h1 != h2)
    }

    @Test func hash_differsBySalt() {
        let h1 = PINAuth.hash(pin: "1234", salt: PINAuth.newSalt())
        let h2 = PINAuth.hash(pin: "1234", salt: PINAuth.newSalt())
        #expect(h1 != h2)
    }

    // MARK: - Verify

    @Test func verify_acceptsCorrectPIN() {
        let salt = PINAuth.newSalt()
        let h = PINAuth.hash(pin: "1234", salt: salt)!
        #expect(PINAuth.verify(pin: "1234", hash: h, salt: salt))
    }

    @Test func verify_rejectsWrongPIN() {
        let salt = PINAuth.newSalt()
        let h = PINAuth.hash(pin: "1234", salt: salt)!
        #expect(!PINAuth.verify(pin: "1235", hash: h, salt: salt))
    }

    @Test func verify_rejectsWrongSalt() {
        let salt = PINAuth.newSalt()
        let otherSalt = PINAuth.newSalt()
        let h = PINAuth.hash(pin: "1234", salt: salt)!
        #expect(!PINAuth.verify(pin: "1234", hash: h, salt: otherSalt))
    }

    @Test func verify_rejectsTruncatedHash() {
        let salt = PINAuth.newSalt()
        let h = PINAuth.hash(pin: "1234", salt: salt)!
        let truncated = h.prefix(h.count - 1)
        #expect(!PINAuth.verify(pin: "1234", hash: Data(truncated), salt: salt))
    }
}
