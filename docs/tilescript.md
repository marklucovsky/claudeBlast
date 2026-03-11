# TileScript: Demo & Test Automation System

## Goals
1. **Demo automation** — Hand-authored YAML scripts drive the app hands-free for live presentations
2. **Test harness** — Programmatically generated bulk scenarios (e.g., 200K cache entries) for scale testing
3. **Debugger-style stepping** — Pause, step over/into, continue, rewind for fine-grained control

## Script Format (YAML via Yams SPM)

```yaml
name: Basic AAC Demo
description: Child requesting food from mom
audio: on
tileWait: .human
sentenceWait: .human

script:
  - tiles:
    - <home>, mom, <food>, pizza
    - pizza, fries
    - pizza, fries
    - <home>, mom, <places>, playground
  - comment: Now bulk loading
  - tileWait: .instant
  - sentenceWait: .instant
  - tiles: {count: 20000, source: most-common, length: 2-4}
```

### Tiles syntax
- Each row = one utterance: optional `<page>` nav mixed with tile keys
- Auto-clear after each row's sentence completes
- `<angle_brackets>` = navigate to page
- Bare words = tile taps via `engine.addTile()`
- Repeated rows test escalation naturally

### Timing presets
| Preset | tileWait | sentenceWait |
|--------|----------|--------------|
| `.human` | ~800ms | ~3s |
| `.fast` | ~100ms | ~500ms |
| `.instant` | 0ms | 0ms |
| explicit | `500ms`, `2s` | `500ms`, `2s` |

### Global settings (overridable inline)
| Setting | Values | Effect |
|---------|--------|--------|
| `audio` | `on`/`off` | Toggle engine audioEnabled |
| `tileWait` | preset or duration | Delay between tile taps |
| `sentenceWait` | preset or duration | Delay after sentence generates |
| `provider` | `mock`/`openai` | Switch sentence provider |
| `scene` | scene name | Activate a named scene |

### Inline commands
| Command | Effect |
|---------|--------|
| `tiles:` (rows) | Sequence of utterances |
| `tiles:` (bulk) | `{count, source, length}` → BulkCacheGenerator |
| `clear` | Explicit clearSelection() |
| `comment` | Show text overlay on HUD |
| `wait` | Explicit pause |
| Settings | Override globals mid-script |

## Architecture

### Key Types
- **NavigationCoordinator** — Shared nav state extracted from TileGridView
- **TileScript** — Parsed script model
- **TileScriptParser** — YAML → TileScript (Yams)
- **TileScriptRunner** — @Observable execution engine with debugger-style stepping
- **BulkCacheGenerator** — Direct cache population bypassing engine

### Stepping Model
Position tracked as `(commandIndex, rowIndex)`:
- **Step Over**: Execute current row/command, pause at next
- **Step Into**: Execute one action within a row
- **Continue**: Finish current tiles block, pause at next top-level command
- **Play**: Resume continuous execution

### UI
- **TileScriptView** — New tab: browse curated scripts, configure test runs
- **TileScriptPlaybackOverlay** — Floating HUD on Home tab during playback

## Files
```
claudeBlast/Engine/TileScript/
  TileScriptCommand.swift
  TileScript.swift
  TileScriptParser.swift
  TileScriptRunner.swift
  BulkCacheGenerator.swift
  NavigationCoordinator.swift

claudeBlast/Views/
  TileScriptView.swift
  TileScriptPlaybackOverlay.swift

claudeBlast/Resources/Scripts/
  demo_basic.yaml
  demo_food.yaml
```
