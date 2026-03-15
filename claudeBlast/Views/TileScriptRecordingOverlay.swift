// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptRecordingOverlay.swift
//  claudeBlast
//

import SwiftUI

/// Floating HUD on TileGridView during recording.
/// Only visible when actively recording. Mutually exclusive with playback overlay.
struct TileScriptRecordingOverlay: View {
    @Environment(TileScriptRecorder.self) private var recorder

    var body: some View {
        if recorder.state == .recording {
            recordingPill
        }
    }

    private var recordingPill: some View {
        HStack(spacing: 10) {
            PulsingDot()

            Text("Recording")
                .font(.caption.weight(.medium))

            if recorder.rowCount > 0 {
                Text("\(recorder.rowCount) row\(recorder.rowCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                recorder.stopRecording()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.caption2)
                    Text("Stop")
                        .font(.caption.weight(.medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .fixedSize()
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 4)
        .padding(.bottom, 16)
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
