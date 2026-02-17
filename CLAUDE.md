# Project notes for Claude

## What is Blaster?
Blaster is an AI-powered AAC (Augmentative and Alternative Communication) app for non-verbal children. Children select word tiles, and AI constructs age-appropriate sentences delivered as text and speech. Open source under Apache license.

See `docs/prd.md` for the full product requirements document.
See `reference/` for the original Blaster models, screenshots, vocabulary, and loader code (inspiration, not to copy).

## Build
- Primary scheme: claudeBlast
- Build:
  xcodebuild -scheme "claudeBlast" -configuration Debug build

## Test
- Tests:
  xcodebuild -project claudeBlast.xcodeproj -scheme "claudeBlast" -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2" test

## Rules
- Do not change signing/team settings unless asked.
- Prefer minimal diffs.
- iPad + iPhone: both form factors supported from the start.
- SwiftUI + SwiftData. Target iOS 26+.
- Privacy: no external backend. SwiftData + iCloud only. API calls (OpenAI) are stateless.
- Never commit API keys or secrets.
