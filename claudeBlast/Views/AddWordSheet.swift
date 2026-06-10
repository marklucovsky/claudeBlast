// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AddWordSheet.swift
//  claudeBlast
//
//  Create a caregiver vocabulary word inline while authoring a page. Handles the
//  key/word-class collision rule (see decision in the vocab-extensions plan):
//   - no collision               → plain new key
//   - collision, SAME word class → it's the same item; offer to add the existing one
//   - collision, DIFFERENT class → homograph; mint `<key>_<wordClass>`, label unchanged
//  Optionally attaches a photo (pick → square crop → CloudKit-safe compress) so a
//  word + its picture can land in one step.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddWordSheet: View {
    let initialWord: String
    let existingTiles: [TileModel]
    /// Selectable word classes (no "all").
    let wordClasses: [String]
    let defaultWordClass: String
    /// Called with the created (or existing-duplicate) tile to place on the page.
    let onCommit: (TileModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var resolver

    @State private var displayName: String
    @State private var wordClass: String
    @State private var duplicateMessage: String?

    // Inline photo (held until the word is created).
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropTarget: CropTarget?
    @State private var processedPhoto: Data?
    @State private var photoPreview: UIImage?
    @State private var photoError: String?

    private struct CropTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    init(initialWord: String,
         existingTiles: [TileModel],
         wordClasses: [String],
         defaultWordClass: String,
         onCommit: @escaping (TileModel) -> Void) {
        self.initialWord = initialWord
        self.existingTiles = existingTiles
        self.wordClasses = wordClasses
        self.defaultWordClass = defaultWordClass
        self.onCommit = onCommit
        _displayName = State(initialValue: initialWord.trimmingCharacters(in: .whitespacesAndNewlines))
        _wordClass = State(initialValue: defaultWordClass)
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Word", text: $displayName)
                        .textInputAutocapitalization(.never)
                }

                Section("Type") {
                    Picker("Word class", selection: $wordClass) {
                        ForEach(wordClasses, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Photo") {
                    if let photoPreview {
                        HStack {
                            Image(uiImage: photoPreview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Spacer()
                            Button(role: .destructive) {
                                processedPhoto = nil
                                self.photoPreview = nil
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photoPreview == nil ? "Add Photo" : "Replace Photo",
                              systemImage: "photo.badge.plus")
                    }
                    if let photoError {
                        Text(photoError).font(.caption).foregroundStyle(.red)
                    }
                    Text("Optional. A photo shows on this tile everywhere it appears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let duplicateMessage {
                    Section {
                        Text(duplicateMessage)
                            .font(.callout)
                        Button("Add the existing word") { addExistingDuplicate() }
                    }
                }
            }
            .navigationTitle("New Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: displayName) { _, _ in duplicateMessage = nil }
            .onChange(of: wordClass) { _, _ in duplicateMessage = nil }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .fullScreenCover(item: $cropTarget) { target in
                SquareImageCropper(
                    image: target.image,
                    onCrop: { square in
                        cropTarget = nil
                        applyCrop(square)
                    },
                    onCancel: { cropTarget = nil }
                )
            }
        }
    }

    // MARK: - Create

    private func create() {
        let base = TileModel.normalizeKey(trimmedName)
        guard !base.isEmpty else { return }

        let finalKey: String
        if let existing = existingTiles.first(where: { $0.key == base }) {
            if existing.wordClass == wordClass {
                // Same item already in the system — don't duplicate.
                duplicateMessage = "“\(existing.displayName)” already exists as a \(existing.wordClass) tile."
                return
            }
            // Homograph: same spelling, different class → mint a distinct key.
            finalKey = uniqueKey(base: "\(base)_\(wordClass)")
        } else {
            finalKey = base
        }

        let tile = TileModel(key: finalKey, value: trimmedName, wordClass: wordClass)
        tile.isSystem = false
        if let processedPhoto {
            tile.userImageData = processedPhoto
        }
        modelContext.insert(tile)
        try? modelContext.save()
        if processedPhoto != nil {
            resolver.invalidatePhoto(for: finalKey)
        }
        onCommit(tile)
        dismiss()
    }

    private func addExistingDuplicate() {
        let base = TileModel.normalizeKey(trimmedName)
        guard let existing = existingTiles.first(where: { $0.key == base && $0.wordClass == wordClass })
        else { return }
        onCommit(existing)
        dismiss()
    }

    /// Ensure `base` is unique against existing tiles; append _2, _3, … if taken.
    private func uniqueKey(base: String) -> String {
        let keys = Set(existingTiles.map(\.key))
        guard keys.contains(base) else { return base }
        var n = 2
        while keys.contains("\(base)_\(n)") { n += 1 }
        return "\(base)_\(n)"
    }

    // MARK: - Photo

    private func loadPhoto(_ item: PhotosPickerItem) async {
        photoError = nil
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoError = "Couldn't read that photo."
                return
            }
            cropTarget = CropTarget(image: image)
        } catch {
            photoError = "Couldn't read that photo."
        }
    }

    private func applyCrop(_ square: UIImage) {
        photoError = nil
        do {
            let data = try TilePhotoProcessor.process(square)
            processedPhoto = data
            photoPreview = UIImage(data: data)
        } catch let err as TilePhotoProcessor.ProcessError {
            photoError = err.errorDescription
        } catch {
            photoError = "Couldn't process that photo."
        }
    }
}
