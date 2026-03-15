// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptPlaybackOverlay.swift
//  claudeBlast
//

import SwiftUI

/// Floating playback controls shown on the Home tab during TileScript execution.
struct TileScriptPlaybackOverlay: View {
    @Environment(TileScriptRunner.self) private var runner

    @State private var isExpanded: Bool = true

    var body: some View {
        switch runner.state {
        case .idle:
            EmptyView()

        case .running:
            runningHUD

        case .paused:
            if isExpanded {
                pausedControls
            } else {
                pausedPill
            }

        case .finished:
            finishedHUD
        }
    }

    // MARK: - Running HUD

    private var runningHUD: some View {
        HStack(spacing: 12) {
            Button { runner.pause() } label: {
                Image(systemName: "pause.fill")
                    .font(.body)
            }

            Button { runner.stop() } label: {
                Image(systemName: "stop.fill")
                    .font(.body)
            }

            Divider().frame(height: 20)

            positionLabel

            if let comment = runner.currentComment {
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let progress = runner.bulkProgress {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .frame(width: 80)
                Text("\(progress.completed)/\(progress.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if runner.bulkDuplicates > 0 {
                    Text("(\(runner.bulkDuplicates) dups)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 4)
        .padding(.bottom, 16)
    }

    // MARK: - Paused (Expanded)

    private var pausedControls: some View {
        VStack(spacing: 8) {
            positionLabel

            // Show upcoming command: either a tile row with highlighted action, or a description
            commandPreview

            HStack(spacing: 16) {
                controlButton("play.fill", label: "Play") { runner.resume() }
                controlButton("forward.frame.fill", label: "Step") { runner.stepOver() }
                controlButton("arrow.down.to.line", label: "Into") { runner.stepInto() }
                controlButton("forward.end.fill", label: "Cont") { runner.continueToEnd() }

                Divider().frame(height: 30)

                controlButton("backward.end.fill", label: "Rewind") { runner.rewind() }
                controlButton("stop.fill", label: "Stop") { runner.stop() }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
        .padding(.bottom, 16)
        .onTapGesture {} // prevent pass-through
    }

    /// Shows what's about to execute — either a tile row with highlighted token or a text description.
    @ViewBuilder
    private var commandPreview: some View {
        if let row = runner.currentRow {
            VStack(spacing: 4) {
                // Row position within the tiles block
                if runner.currentRowCount > 1 {
                    Text("Row \(runner.rowIndex + 1)/\(runner.currentRowCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Tile tokens with the next-to-execute action highlighted
                tileRowTokens(row: row, activeIndex: runner.actionIndex)

                // Line comment in italics
                if let comment = row.comment {
                    Text(comment)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        } else if let desc = runner.nextCommandDescription {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }

        // Last comment for context
        if runner.currentRow != nil, let comment = runner.currentComment {
            Text(comment)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    /// Render tile row tokens as a horizontal flow, highlighting the action at `activeIndex`.
    private func tileRowTokens(row: TileRow, activeIndex: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(row.tokens.enumerated()), id: \.offset) { index, token in
                tokenView(token: token, index: index, activeIndex: activeIndex)

                if index < row.tokens.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    private func tokenView(token: String, index: Int, activeIndex: Int) -> some View {
        let isNav = token.hasPrefix("<")
        let isActive = index == activeIndex
        let isDone = index < activeIndex

        let fgStyle: Color = isActive ? .primary : isDone ? .gray : .secondary
        let bgColor: Color = {
            if isActive { return isNav ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2) }
            if isDone { return Color.gray.opacity(0.08) }
            return Color.clear
        }()
        let borderColor: Color = {
            if isActive { return isNav ? Color.blue.opacity(0.5) : Color.orange.opacity(0.5) }
            return Color.clear
        }()

        return Text(token)
            .font(.caption.monospaced())
            .fontWeight(isActive ? .bold : .regular)
            .foregroundStyle(fgStyle)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(bgColor))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(borderColor, lineWidth: 1))
    }

    // MARK: - Paused (Collapsed Pill)

    private var pausedPill: some View {
        Button {
            withAnimation { isExpanded = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pause.fill")
                    .font(.caption)
                Text("Paused")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Finished

    private var finishedHUD: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Script finished")
                .font(.caption.weight(.medium))

            Button { runner.rewind() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }

            Button { runner.stop() } label: {
                Text("Dismiss")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 4)
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private var positionLabel: some View {
        Text("Command \(runner.commandIndex + 1)/\(runner.totalCommands)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
    }

    private func controlButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 36)
        }
        .buttonStyle(.plain)
    }
}
