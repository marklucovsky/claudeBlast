// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIKeyEntrySection.swift
//  claudeBlast
//
//  Shared OpenAI API-key *action* control, used by the onboarding wizard and
//  Admin → Device. It is deliberately lean: the only thing that belongs inside
//  Blaster's flow is creating a key on the Platform and pasting it here ("Get
//  an API Key for Blaster"). The prerequisites — a funded OpenAI Platform
//  account (separate from ChatGPT), with billing — happen on OpenAI's site and
//  are explained in OpenAIKeySetupGuide, linked from here and surfaced earlier
//  on the welcome screen.
//
//  Polish from the GTM plan: paste-from-clipboard, a deep link to create a key,
//  live validation with a friendly status line, and a cost estimate. Binds to
//  the caller's key string; callers own persistence (Keychain) via their own
//  onChange, so this view only edits the binding and reports validity.

import SwiftUI
import UIKit

struct OpenAIKeyEntrySection: View {
    @Binding var apiKey: String
    /// Onboarding shows the cost estimate; Admin can hide it to stay compact.
    var showCostEstimate: Bool = true

    @State private var outcome: OpenAIKeyValidator.Outcome?
    @State private var isChecking = false
    @State private var validateTask: Task<Void, Never>?
    @State private var showGuide = false

    /// Deep link straight to key creation for someone who already has a funded
    /// Platform account — the common returning case.
    private static let keysURL = URL(string: "https://platform.openai.com/api-keys")!
    /// A key is only worth a network round-trip once it's plausibly complete.
    private static let minPlausibleLength = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs a key from a funded OpenAI Platform account (separate from ChatGPT).")
                .font(.caption)
                .foregroundStyle(.secondary)

            // The in-flow action: create a key (assumes the prerequisite).
            Link(destination: Self.keysURL) {
                Label("Get an API Key for Blaster", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Paste it back here.
            HStack(spacing: 8) {
                SecureField("Paste your key (sk-…)", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { scheduleValidation(immediate: true) }

                Button {
                    if let pasted = UIPasteboard.general.string {
                        apiKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        scheduleValidation(immediate: true)
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Paste API key")
            }

            statusLine

            HStack {
                Button {
                    showGuide = true
                } label: {
                    Label("First-time setup guide", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 8)
                if showCostEstimate {
                    Text("≈ $0.10–0.50 / month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Re-validate (debounced) as the field changes — covers typing and
        // programmatic edits. Paste/submit trigger an immediate check.
        .onChange(of: apiKey) { scheduleValidation(immediate: false) }
        .onAppear {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minPlausibleLength {
                scheduleValidation(immediate: true)
            }
        }
        .sheet(isPresented: $showGuide) { OpenAIKeySetupSheet() }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLine: some View {
        if isChecking {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking key…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let outcome {
            Label(outcome.friendlyMessage, systemImage: statusIcon(outcome))
                .font(.caption)
                .foregroundStyle(statusColor(outcome))
        }
    }

    private func statusIcon(_ outcome: OpenAIKeyValidator.Outcome) -> String {
        switch outcome {
        case .valid:        return "checkmark.seal.fill"
        case .invalidKey:   return "xmark.octagon.fill"
        case .rateLimited:  return "clock.fill"
        case .networkError: return "wifi.exclamationmark"
        case .unexpected:   return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ outcome: OpenAIKeyValidator.Outcome) -> Color {
        switch outcome {
        case .valid:        return .green
        case .invalidKey:   return .red
        default:            return .orange
        }
    }

    // MARK: - Validation

    /// Debounce typing; validate paste/submit immediately. Clears status when
    /// the field is empty or too short to be a real key.
    private func scheduleValidation(immediate: Bool) {
        validateTask?.cancel()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= Self.minPlausibleLength else {
            isChecking = false
            outcome = nil
            return
        }
        validateTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(900))
                if Task.isCancelled { return }
            }
            isChecking = true
            outcome = nil
            let result = await OpenAIKeyValidator.validate(key)
            if Task.isCancelled { return }
            isChecking = false
            outcome = result
        }
    }
}
