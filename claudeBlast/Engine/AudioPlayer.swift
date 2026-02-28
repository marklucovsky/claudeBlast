// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AudioPlayer.swift
//  claudeBlast
//

import AVFoundation

@Observable
@MainActor
final class AudioPlayer {
    private(set) var isPlaying: Bool = false
    private var player: AVAudioPlayer?
    private var delegate: PlayerDelegate?

    func play(data: Data) {
        stop()

        do {
            let audioPlayer = try AVAudioPlayer(data: data)
            let playerDelegate = PlayerDelegate { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                }
            }
            audioPlayer.delegate = playerDelegate
            self.player = audioPlayer
            self.delegate = playerDelegate
            audioPlayer.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        delegate = nil
        isPlaying = false
    }
}

// MARK: - AVAudioPlayerDelegate (NSObject subclass required)

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, Sendable {
    let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
