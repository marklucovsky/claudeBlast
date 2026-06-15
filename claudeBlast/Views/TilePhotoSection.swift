// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TilePhotoSection.swift
//  claudeBlast
//
//  Reusable Form section for attaching / removing a caregiver photo on a tile.
//  A photo overrides the tile's picture everywhere it appears (see
//  TileImageResolver) and syncs across the family's devices via CloudKit.
//
//  Presentation split: this section ONLY hosts the PhotosPicker + remove button.
//  Picking reports the chosen image up via `onPick`; the HOST presents the
//  square cropper at its root and commits via `TilePhotoCommit`. Presenting the
//  cropper from inside a Form Section (a non-view anchor) while the system photo
//  picker is still dismissing causes "already presenting" modal conflicts/crashes.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct TilePhotoSection: View {
    @Bindable var tile: TileModel
    /// Called with a freshly picked (uncropped) image. The host presents the
    /// cropper and, on confirm, calls `TilePhotoCommit.apply`.
    let onPick: (UIImage) -> Void

    @Environment(TileImageResolver.self) private var resolver
    @Environment(\.modelContext) private var modelContext

    @State private var pickerItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var imageDetail = ""

    private var apiKey: String { OpenAIKeyVault.currentKey() ?? "" }

    var body: some View {
        Section("Photo") {
            if tile.userImageData != nil {
                Label("Custom photo set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button(role: .destructive, action: removePhoto) {
                    Label("Remove Photo", systemImage: "trash")
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(tile.userImageData == nil ? "Add Photo" : "Replace Photo",
                      systemImage: "photo.badge.plus")
            }
            .disabled(isLoading || isGenerating)

            if !apiKey.isEmpty {
                Button {
                    Task { await generateImage() }
                } label: {
                    Label(tile.userImageData == nil ? "Generate with AI" : "Regenerate with AI",
                          systemImage: "wand.and.stars")
                }
                .disabled(isLoading || isGenerating)

                TextField("Add a detail to refine (optional)", text: $imageDetail, axis: .vertical)
                    .font(.caption)
                    .lineLimit(1...2)
                    .disabled(isLoading || isGenerating)
                    .onChange(of: imageDetail) { _, value in
                        if value.count > TileImageGenerator.maxDetailLength {
                            imageDetail = String(value.prefix(TileImageGenerator.maxDetailLength))
                        }
                    }
                if imageDetail.count >= TileImageGenerator.detailCounterThreshold {
                    Text("\(imageDetail.count)/\(TileImageGenerator.maxDetailLength)")
                        .font(.caption2)
                        .foregroundStyle(imageDetail.count >= TileImageGenerator.maxDetailLength ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if isLoading || isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                    if isGenerating {
                        Text("Generating image…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("A photo replaces this tile's picture everywhere it appears, on every device signed in to your iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
    }

    /// Decode the picked item to a UIImage and hand it up for cropping. Awaiting
    /// the transfer also lets the system photo picker finish dismissing before
    /// the host presents the cropper.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't read that photo."
                return
            }
            onPick(image)
        } catch {
            errorMessage = "Couldn't read that photo."
        }
    }

    /// Generate a first-pass image for this tile and store it directly — the
    /// result is already a centered square, so no crop step.
    private func generateImage() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let image = try await TileImageGenerator.generate(
                displayName: tile.displayName, wordClass: tile.wordClass,
                imageSet: resolver.activeSet, detail: imageDetail, apiKey: apiKey)
            errorMessage = TilePhotoCommit.apply(
                image, to: tile, context: modelContext, resolver: resolver)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't generate an image."
        }
    }

    private func removePhoto() {
        tile.userImageData = nil
        try? modelContext.save()
        resolver.invalidatePhoto(for: tile.key)
    }
}

// MARK: - Commit helper (shared by every host that uses TilePhotoSection)

enum TilePhotoCommit {
    /// Compress the cropped square into a CloudKit-safe blob and store it on the
    /// tile. Returns a user-facing error string on failure, or nil on success.
    @MainActor
    static func apply(_ square: UIImage,
                      to tile: TileModel,
                      context: ModelContext,
                      resolver: TileImageResolver) -> String? {
        do {
            let processed = try TilePhotoProcessor.process(square)
            tile.userImageData = processed
            try context.save()
            resolver.invalidatePhoto(for: tile.key)
            return nil
        } catch let err as TilePhotoProcessor.ProcessError {
            return err.errorDescription
        } catch {
            return "Couldn't save that photo."
        }
    }
}
