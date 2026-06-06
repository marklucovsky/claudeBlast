// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminGate.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import LocalAuthentication

/// Wraps Admin content with a Face ID / PIN challenge when the active
/// `DeviceProfile.requireFaceIDForAdmin` flag is set.
///
/// Flow on first appearance:
/// 1. If gating isn't required (Personal device, or Therapist that didn't
///    opt in), pass through to content immediately.
/// 2. Otherwise, attempt `LAContext` biometric evaluation. Success → content.
/// 3. On biometric failure / cancel / unavailable, switch to PIN entry.
/// 4. If no PIN has been set up yet, switch to PIN setup mode (enter twice).
///
/// The gate's `didAuth` state is local to one Admin presentation — if the
/// user dismisses Admin and re-enters, they re-authenticate. This is the
/// "cold-launch" posture; a soft re-entry timeout could relax that later.
struct AdminGate<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var deviceProfiles: [DeviceProfile]

    @State private var didAuth = false
    @State private var biometricsAttempted = false
    @State private var biometricsAvailable = false
    @State private var showingPIN = false
    @State private var pinInput = ""
    @State private var pinConfirm = ""
    @State private var errorMessage: String?
    @FocusState private var pinFieldFocused: Bool

    @ViewBuilder let content: () -> Content

    private var device: DeviceProfile? { deviceProfiles.first }
    private var needsAuth: Bool { device?.requireFaceIDForAdmin == true }
    private var hasPIN: Bool {
        device?.adminPINHash != nil && device?.adminPINSalt != nil
    }

    var body: some View {
        Group {
            if didAuth || !needsAuth {
                content()
            } else {
                challengeView
            }
        }
    }

    // MARK: - Challenge UI

    private var challengeView: some View {
        ZStack {
            // Opaque backdrop so the underlying tile grid doesn't bleed
            // through the fullScreenCover. systemBackground adapts to light
            // and dark mode.
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Admin is locked")
                    .font(.title.bold())
                Text(challengeSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if showingPIN {
                    pinSection
                } else {
                    Button("Try Face ID") {
                        Task { await tryBiometrics() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Use PIN") { showingPIN = true; pinFieldFocused = true }
                        .buttonStyle(.borderless)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if !biometricsAttempted {
                biometricsAttempted = true
                await tryBiometrics()
            }
        }
    }

    private var challengeSubtitle: String {
        if hasPIN {
            return biometricsAvailable
                ? "Use Face ID, or enter your PIN."
                : "Enter your PIN."
        } else {
            return biometricsAvailable
                ? "Use Face ID. Set up a PIN now as a backup for when Face ID isn't available."
                : "Face ID isn't enrolled on this device. Set up a PIN to unlock Admin."
        }
    }

    @ViewBuilder
    private var pinSection: some View {
        if hasPIN {
            pinEntryView
        } else {
            pinSetupView
        }
    }

    private var pinEntryView: some View {
        VStack(spacing: 12) {
            SecureField("4–6 digit PIN", text: $pinInput)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .focused($pinFieldFocused)
                .onSubmit(submitPINEntry)
            Button("Unlock", action: submitPINEntry)
                .buttonStyle(.borderedProminent)
                .disabled(!PINAuth.isValidPINShape(pinInput))
        }
        .padding(.horizontal, 32)
    }

    private var pinSetupView: some View {
        VStack(spacing: 12) {
            Text("Choose a 4–6 digit PIN. Use it when Face ID isn't available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            SecureField("PIN", text: $pinInput)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .focused($pinFieldFocused)
            SecureField("Confirm PIN", text: $pinConfirm)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitPINSetup)
            Button("Set PIN", action: submitPINSetup)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmitPINSetup)
        }
        .padding(.horizontal, 32)
    }

    private var canSubmitPINSetup: Bool {
        PINAuth.isValidPINShape(pinInput) && pinInput == pinConfirm
    }

    // MARK: - Actions

    private func tryBiometrics() async {
        let ctx = LAContext()
        var policyError: NSError?
        let canEval = ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &policyError)
        biometricsAvailable = canEval
        guard canEval else {
            // No biometric hardware enrolled — go straight to PIN.
            showingPIN = true
            pinFieldFocused = true
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Admin")
            if ok {
                didAuth = true
            } else {
                showingPIN = true
                pinFieldFocused = true
            }
        } catch {
            // User canceled, failed, or the system blocked — fall back to PIN.
            showingPIN = true
            pinFieldFocused = true
        }
    }

    private func submitPINEntry() {
        guard let device,
              let storedHash = device.adminPINHash,
              let salt = device.adminPINSalt else {
            errorMessage = "PIN not set up yet — restart and re-enter Admin."
            return
        }
        if PINAuth.verify(pin: pinInput, hash: storedHash, salt: salt) {
            didAuth = true
            pinInput = ""
            errorMessage = nil
        } else {
            errorMessage = "Incorrect PIN."
            pinInput = ""
        }
    }

    private func submitPINSetup() {
        guard let device else { return }
        guard canSubmitPINSetup else {
            errorMessage = "PINs must match and be 4–6 digits."
            return
        }
        let salt = PINAuth.newSalt()
        guard let hash = PINAuth.hash(pin: pinInput, salt: salt) else {
            errorMessage = "Could not save PIN."
            return
        }
        device.adminPINSalt = salt
        device.adminPINHash = hash
        device.modifiedAt = .now
        didAuth = true
        pinInput = ""
        pinConfirm = ""
        errorMessage = nil
    }
}
