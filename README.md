# Blaster

**AI-powered AAC app for non-verbal children**

## What it does

Blaster lets children communicate by tapping word tiles on a visual grid. After selecting up to four tiles, an AI model (OpenAI GPT-4o) constructs an age-appropriate sentence and speaks it aloud. The app is designed for iPad and iPhone, with a child-facing tile grid and a parent/caregiver admin panel.

## Status

Early development. Data is currently held in memory only and reloaded from bundled vocabulary on every launch. The app is not yet on the App Store.

## Requirements

- Xcode 16+
- iOS 26 Simulator (iPad Pro 11-inch M5 recommended) or a physical device running iOS 26
- OpenAI API key (optional — a mock provider is available for development without a key)

## Build

```sh
# Build
xcodebuild -scheme "claudeBlast" -configuration Debug build

# Test
xcodebuild -project claudeBlast.xcodeproj -scheme "claudeBlast" \
  -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2" test
```

## Architecture

The app uses SwiftUI + SwiftData targeting iOS 26+. See [CLAUDE.md](CLAUDE.md) for the full architecture reference, including data models, bootstrap flow, AI engine, and view structure.

## Image Licensing

> **Important:** Most tile images are ARASAAC pictograms created by Sergio Palao, distributed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). This license permits **non-commercial use only**. App Store distribution constitutes commercial use and requires replacing these images with commercially-licensed imagery before submission. See [NOTICE](NOTICE) for full attribution details.

Approximately 20 tiles were generated with OpenAI DALL-E 3 and are commercially usable per OpenAI's Terms of Service.

## License

The source code is licensed under the **Apache License 2.0**. See [LICENSE](LICENSE).

Tile images have separate licensing terms as described above and in [NOTICE](NOTICE).

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
