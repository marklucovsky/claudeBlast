# Blaster

**AI-powered AAC app for non-verbal children**

Blaster lets children communicate by tapping word tiles on a visual grid. After selecting tiles, an AI model constructs an age-appropriate sentence and speaks it aloud. The app is designed for iPad and iPhone, with a child-facing tile grid and a parent/caregiver admin panel behind a hidden menu.

Open source under the Apache License 2.0.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| macOS Sequoia or later | |
| Xcode 16.3+ | With iOS 26 SDK and simulator |
| Apple Developer account | Free account works for simulator; paid ($99/yr) for device |
| OpenAI API key | Optional — mock provider works for development without one |
| Python 3.10+ | Only needed for image generation tools |
| GitHub account | For forking and pull requests |

---

## Quick Start

```bash
git clone https://github.com/marklucovsky/claudeBlast.git
cd claudeBlast
open claudeBlast.xcodeproj
```

In Xcode:
1. Select the **iPad Pro 11-inch (M5)** simulator from the device picker
2. Press **Cmd+R** to build and run

The app launches with the full default vocabulary (473 tiles, 12 pages). No configuration needed — the mock sentence provider is active by default.

---

## Configuring the OpenAI API Key

AI sentence generation requires an OpenAI API key. Two ways to set it:

**Option 1: Xcode scheme environment variable (recommended for development)**

1. Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
2. Add `OPENAI_API_KEY` = your key
3. Build and run — the key is persisted to UserDefaults automatically

**Option 2: In-app Admin panel**

1. Triple-tap the top-left corner of the tile grid to reveal the menu
2. Tap the hamburger icon → Admin
3. Set the provider to "OpenAI" and paste your key

Without a key, the app uses `MockSentenceProvider` which returns instant placeholder responses. This is fine for working on UI, layout, navigation, and anything that doesn't need real AI output.

---

## Configuring Claude Code

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) is the AI coding assistant used to build Blaster. It reads `CLAUDE.md` automatically for project context.

**Install:**

```bash
npm install -g @anthropic-ai/claude-code
```

**Key files Claude uses:**
- `CLAUDE.md` — architecture reference, build commands, project rules
- `.claude/` — memory and plans persisted across sessions

### Worktree-based workflow (recommended)

Claude Code works best with git worktrees, especially when running multiple Claude sessions on different features simultaneously. Each worktree gets its own working directory and branch, so sessions don't conflict.

```bash
# Start a new feature (from the main repo directory)
git worktree add ../cb-feelings -b feature/feelings
cd ../cb-feelings
claude   # launch Claude Code in the worktree

# Start another feature in parallel
git worktree add ../cb-import-fix -b fix/import-error
cd ../cb-import-fix
claude

# When done, merge and clean up
cd ../claudeBlast          # back to main repo
git worktree remove ../cb-feelings
```

Each worktree shares the same git history but has an independent working tree and branch. This is how we run multiple Claude sessions without stepping on each other.

---

## Project Structure

```
claudeBlast/
  claudeBlastApp.swift      # App entry point, environment setup
  ContentView.swift          # Root view: hidden hamburger nav, tile grid
  PreviewHelpers.swift       # Shared Xcode preview environment
  Models/                    # SwiftData models (TileModel, PageModel, BlasterScene, etc.)
  Engine/                    # AI sentence engine, providers, TileScript runner
    Providers/               # OpenAI, Mock, Apple sentence providers
    TileScript/              # YAML demo script parser, runner, recorder
    Cache/                   # Sentence cache manager
  Views/                     # All SwiftUI views
  Services/                  # Bootstrap loader, scene builder/exporter/importer, settings
  Resources/
    vocabulary.json          # 473 tile definitions (key, wordClass)
    pages.json               # 12 page layouts with tile assignments
    sentence_prompt.json     # System prompt template for AI
    Scripts/                 # Curated TileScript YAML demos
docs/
  prd.md                     # Product requirements document
  gtm.md                     # Go-to-market plan
tools/                       # Python scripts for image generation and review
```

---

## Building and Testing

```bash
# Build
xcodebuild -scheme "claudeBlast" -configuration Debug build

# Run tests
xcodebuild -project claudeBlast.xcodeproj -scheme "claudeBlast" \
  -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2" test
```

The project has one SPM dependency: [Yams](https://github.com/jpsim/Yams) (YAML parser for TileScript). It resolves automatically on first build.

---

## Image Tile Generation

Blaster supports multiple image sets. The default is ARASAAC pictograms; a DALL-E-generated "playful 3D" set is also available. Image sets are switchable in the Admin panel.

**Where images live:**
- Default set: `Assets.xcassets/{key}.imageset/{key}.png`
- Additional sets: `TileImageSets/{set_name}/{key}.png` (bundled as resources)

### Tools

All tools are in `tools/` and require Python 3 + an `OPENAI_API_KEY` environment variable for generation.

| Script | What it does |
|---|---|
| `download_arasaac.py` | Download ARASAAC pictograms for all vocabulary tiles |
| `generate_dalle.py` | Generate custom DALL-E 3 tiles using prompts from `prompts.json` |
| `generate_sets.py` | Batch-generate complete styled tile sets (playful_3d, high_contrast) |
| `optimize_tiles.py` | Resize master images (1024px) to app-ready (512px) with PNG optimization |
| `contact_sheet.py` | Generate grid contact sheets for visual review |
| `review_tiles.py` | Review workflow: build sheets, flag rejects, track status |
| `build_review_page.py` | Build interactive HTML review page with approve/reject UI |

**Generating a new tile set:**

```bash
cd tools
export OPENAI_API_KEY=sk-...
python3 generate_sets.py          # generates master images
python3 optimize_tiles.py         # resizes for app bundle
```

---

## TileScript Demos

TileScript is a YAML-based scripting system for hands-free app demos. Scripts automate tile taps, page navigation, and sentence generation — useful for presentations, testing, and recording reusable demo sequences.

### Curated demos

Bundled YAML scripts live in `Resources/Scripts/`:

| File | Description |
|---|---|
| `demo_basic.yaml` | Child requesting food from mom — navigation, sentence generation, escalation |
| `demo_food.yaml` | Food ordering scenario with increasing urgency |

### YAML format

```yaml
name: Basic AAC Demo
description: Child requesting food from mom
audio: on
tileWait: .human       # .human = manual step, or a duration like 1.0
sentenceWait: .human

script:
  - comment: Basic AAC interaction flow
  - tiles:
    - <home>, mom, <food>, pizza       # angle brackets = navigation tap
    - pizza, fries                      # same page — combo order
    - pizza, fries                      # repeat triggers escalation
```

### Adding a new demo

1. Create a `.yaml` file in `Resources/Scripts/`
2. Add it to the Xcode project (it's in a file-system-synchronized group, so just placing it in the directory works)
3. Add a `ScriptInfo` entry in `TileScriptView.swift`'s `curatedScripts` array:
   ```swift
   ScriptInfo(name: "My Demo", description: "What it shows", resourceName: "my_demo")
   ```

### Record mode

You can also record demos by interacting with the app:

1. Open the TileScript tab → tap **Record Demo**
2. Navigate and tap tiles naturally
3. Tap **Stop** — the recording is serialized to YAML and saved

---

## Vocabulary and Pages

The default vocabulary is defined in two JSON files in `Resources/`:

**`vocabulary.json`** — 473 tile definitions:
```json
[
  { "key": "eat", "wordClass": "actions" },
  { "key": "pizza", "wordClass": "food" }
]
```

**`pages.json`** — 12 page layouts:
```json
[
  {
    "key": "home",
    "pageTiles": [
      { "key": "eat", "link": "food", "isAudible": true },
      { "key": "people", "link": "people", "isAudible": false }
    ]
  }
]
```

### Adding a new tile

1. Add an entry to `vocabulary.json` with a unique `key` and `wordClass`
2. Add the tile image to `Assets.xcassets/{key}.imageset/{key}.png`
3. Reference the tile in `pages.json` on the appropriate page(s)
4. If this is a structural change, bump `currentBootstrapVersion` in `AppSettings.swift` to force a re-bootstrap on next launch

---

## Scene Import/Export

Scenes can be shared between devices as `.blasterscene` files (JSON format: `application/vnd.claudeblast.scene+json`).

**Export:** Open a scene in Admin → tap the share icon in the toolbar → send via iMessage, AirDrop, email, or save to Files.

**Import:** Tap a `.blasterscene` attachment in Messages → share to Blaster. Or use Admin → Import Scene to pick from Files.

The format supports vocabulary extension — scenes can carry new tile definitions (with optional images) that get added to the receiving device's vocabulary on import. See `SceneTransferModels.swift` for the full schema.

---

## Image Licensing

> **Important:** Most tile images are ARASAAC pictograms created by Sergio Palao, distributed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). This license permits **non-commercial use only**. App Store distribution requires replacing these images with commercially-licensed imagery before submission. See [NOTICE](NOTICE) for full attribution.

Approximately 20 tiles were generated with OpenAI DALL-E 3 and are commercially usable per OpenAI's Terms of Service.

## License

Source code is licensed under the **Apache License 2.0**. See [LICENSE](LICENSE).

Tile images have separate licensing terms as described above and in [NOTICE](NOTICE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch naming, PR process, and guidelines.

See [CLAUDE.md](CLAUDE.md) for the full architecture reference.
