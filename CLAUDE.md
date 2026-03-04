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
- You commit, I push to GitHub.
- Always start new features in a feature branch, always off main.

## Current Architecture

### Data model (SwiftData, all in-memory for now)
All models live in `claudeBlast/Models/`.

- **TileModel** — the vocabulary unit. `key` is unique ID and asset name (e.g. `eat`).
  `bundleImage == key` → `Assets.xcassets/{key}.imageset/{key}.png`.
  `value` is the display/speech string. `wordClass` is semantic category only (not layout).
  `userImageData: Data?` for future custom photos.

- **PageTileModel** — junction of TileModel + page-specific behavior.
  `link: String` — if non-empty, tapping navigates to this page key.
  `isAudible: Bool` — if true, tap adds tile to sentence tray.

- **PageModel** — ordered collection of PageTileModel.
  `tileOrder: [String]` (array of PageTileModel IDs) defines display order.
  `orderedTiles` computed property walks tileOrder to return ordered tiles.
  `displayName` doubles as the page's lookup key (e.g. `"home"`, `"actions"`).
  Methods: `removeTile(_:)`, `moveTile(from:to:)`.

- **BlasterScene** — a named set of pages with a designated home page.
  `homePageKey: String` — displayName of the page shown first when scene is active.
  `isDefault: Bool` — the built-in vocabulary scene, never deleted.
  `isActive: Bool` — only one scene active at a time; `activate(context:)` enforces this.
  `pages: [PageModel]` — relationship (nullify delete rule).

- **SentenceCache** — cached AI responses keyed by sorted tile combination.
  `cacheKey` = tile keys sorted alphabetically + joined (order-independent).
  `hitCount` tracks frequency (future: promoted tiles).

- **MetricEvent** — raw event log for future analytics. Not yet surfaced in UI.

**Storage:** `isStoredInMemoryOnly: true` in `claudeBlastApp.swift:25` — data wiped on every launch. Intentional for now; switching to persistent + CloudKit is a planned chunk.

### Bootstrap flow
`BootstrapLoader.loadDefaultVocabulary(context:)` runs at app launch:
1. Decodes `Resources/vocabulary.json` → `[TileModel]` (480 tiles)
2. Decodes `Resources/pages.json` → `[PageModel]` with `PageTileModel` junctions
3. Creates "Default" scene (isDefault, isActive) with all pages
4. Creates "All Tiles (Review)" scene (flat single page, sorted by wordClass)
5. Inserts everything in one `context.transaction {}`

`vocabulary.json` format: `[{ "key": "eat", "wordClass": "actions" }]`
`pages.json` format: `[{ "key": "home", "pageTiles": [{ "key": "eat", "link": "food", "isAudible": false }] }]`
All tile keys must be lowercase. Keys map directly to imageset directory names.

### Tile images
`Assets.xcassets/{key}.imageset/{key}.png` — one imageset per tile.
Source: ARASAAC (CC BY-NC-SA 4.0) for most tiles; DALL-E 3 for ~20 tiles with no good ARASAAC match. Before App Store: replace all with custom DALL-E set to clear license.
Tools: `tools/download_arasaac.py`, `tools/generate_dalle.py`, `tools/prompts.json`.

### SentenceEngine (Observable, MainActor)
Lives in `Engine/SentenceEngine.swift`. Injected as environment object.
- `selectedTiles: [TileSelection]` — current tray selection (max 4)
- Debounce: 350ms after last tile tap → triggers generation
- Cache-first: `SentenceCacheManager.lookup(tiles:)` → instant hit or API call
- Staleness guard: if tiles changed while API was in flight, discard result
- Conversational context: last 5 generated sentences fed back to AI as history
- Repetition escalation: same tile combination tapped repeatedly → escalating urgency in prompt
- Idle timeout: 30s after generation → `clearSelection()`
- `sessionNotes: String` — free-text notes, long-press any tile to append

Provider abstraction: `SentenceProvider` protocol. Implementations:
- `OpenAISentenceProvider` — gpt-4o-mini, returns text only
- `MockSentenceProvider` — instant fake response, no API key needed

Audio: `SpeechSynthesizer.swift` wraps `AVSpeechSynthesizer` for all TTS (sentences + tile preview). Audio session configured with `.playback` + `.spokenAudio` at launch so speech plays regardless of the silent switch. Voice selected in AdminView, persisted in `speechVoiceIdentifier` UserDefaults key.

API key stored in `@AppStorage("openai_api_key")` (UserDefaults). Dev-only acceptable.
Override: set `OPENAI_API_KEY` env var in scheme → takes precedence, skips UI entry.

### Views
- `ContentView` — root TabView with two tabs: child grid (TileGridView) and admin (AdminView)
- `TileGridView` — paginated grid. `tilesPerPage(geo:isLandscape:)` computes from geometry (min tile 72pt). Portrait uses `VStack` (not LazyVStack) for correct snap offsets. Debug builds show breadcrumb navigation trail.
- `TileView` — single tile: image + label. Color-coded by wordClass (see `wordClassColor()` in `SentenceTrayView.swift`). Long-press → note capture sheet.
- `SentenceTrayView` — top tray: mini color-tinted tile chips + generated sentence text + replay/clear buttons. History sheet accessible via clock icon.
- `AdminView` — admin panel: scenes list (activate/delete), cache viewer, session notes, provider/key picker, "Create Sample Scene" button.

### wordClass color mapping (file-private in SentenceTrayView.swift)
actions=orange, describe=green, people=purple, food/meals/fruit/veggie/snacks=red, places=blue, social/feeling/question=pink, navigation=indigo, drinks=cyan, weather=blue-gray, colors=mint, shape=teal, body/health=salmon, toy/games/sports=yellow, art=purple-light, play=yellow, default=gray

### Pages structure (pages.json)
12 pages after merging continuation pages:
home(35), people(20), social(36), actions(108), describe(114), food(48), drinks(11), places(36), play_activities(27), body_health(16), colors_shapes(24), weather(16)
No next_page/previous_page tiles — app's built-in grid paging handles overflow.

### Branches
**RULE: every feature or fix gets its own branch off main. Create the branch before writing any code. No exceptions.**

```
git checkout main && git checkout -b feature/<name>
```

- `main` — stable, direct commits only for trivial single-file fixes
- `feature/local-tts` — replace audio model with gpt-4o-mini + AVSpeechSynthesizer (in progress)
- `scene-editor` — scene & page editor (next after local-tts)

### Known deferred items
- `isStoredInMemoryOnly: true` — intentional, persistence is next planned chunk
- API key in UserDefaults — Keychain deferred to pre-release
- Face ID gate on AdminView — deferred to pre-release
- Scene/page editor — next major feature chunk
- Child profile (name/age/voice) — follows scene editor
