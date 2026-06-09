// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SpeechSynthesizer.swift
//  claudeBlast
//
//  Local TTS via AVSpeechSynthesizer.
//  iOS ships with built-in voices. Enhanced and Premium voices can be
//  downloaded in Settings → Accessibility → Spoken Content → Voices
//  for significantly more natural-sounding speech. Premium voices
//  (iOS 17+) use an on-device neural model and are indistinguishable
//  from cloud TTS; Enhanced voices are a step up from the default.
//  Audio never leaves the device regardless of voice tier.
//

import AVFoundation

@Observable
@MainActor
final class SpeechSynthesizer: NSObject {
    private(set) var isSpeaking: Bool = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak `text`. All voice attributes are optional — pass `nil` to use the
    /// `AVSpeechUtterance` defaults. The engine routes the active child's
    /// `voiceIdentifier`, `ttsRate`, and `ttsVolume` through here on every
    /// utterance so per-child prefs are honored without the synthesizer
    /// needing to know about the resolver.
    func speak(_ text: String,
               voiceIdentifier: String?,
               rate: Float? = nil,
               volume: Float? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        // .playback + .spokenAudio ensures speech is audible regardless of
        // the ringer/silent switch — critical for an AAC communication app.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        if let rate {
            // Clamp to the framework's documented bounds. Out-of-range
            // values throw a runtime assertion in some AVFoundation builds.
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                                 max(AVSpeechUtteranceMinimumSpeechRate, rate))
        }
        if let volume {
            utterance.volume = min(1.0, max(0.0, volume))
        }
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
