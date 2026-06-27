// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftUI

/// Lightweight in-flow sheet for installing an OpenAI API key (paste + live
/// validation via the shared OpenAIKeyEntrySection). The key is written to the
/// device Keychain as it changes; on dismiss the presenting view re-reads
/// OpenAIKeyVault and flips from the "add a key" nudge to the normal
/// generate-art action.
struct APIKeyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = OpenAIKeyVault.currentKey() ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OpenAIKeyEntrySection(apiKey: $apiKey)
                } footer: {
                    Text("Stored only on this device (Keychain). New-word art generation uses it directly — typical cost is well under a cent per image.")
                }
            }
            .navigationTitle("Add an AI Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: apiKey) { OpenAIKeyVault.setKey(apiKey) }
        }
    }
}
