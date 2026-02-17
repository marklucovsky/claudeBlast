# Blaster - Next Gen AAC Communication Device
## Informal PRD (Living Document)

### Mission
Redefine communication for non-verbal children. Open source (Apache license) to give back to the community.

Personal motivation: Built for a granddaughter who benefits from AAC technology. These devices are life-changing.

---

### What Blaster Is
An AI-powered AAC (Augmentative and Alternative Communication) app for non-verbal children. iPad-first. The child selects word tiles, and AI constructs age-appropriate sentences from those selections, delivered as both text and speech.

### What Makes This "Next Gen"
The original Blaster was hand-coded with a fixed 500-word vocabulary and proved the concept. This version rethinks the architecture with AI throughout - not just sentence expansion, but AI-assisted vocabulary creation, therapeutic tools, and adaptive growth.

---

### Core Principles

**1. Stability for the child**
- Fixed tile positions. The child builds muscle memory and spatial patterns.
- No dynamic rearrangement of tiles. Predictability is paramount.
- The grid is the child's voice. It must be reliable.

**2. Intelligence for the ecosystem**
- AI serves the therapists, parents, and teachers who shape the child's communication environment.
- AI generates tile sets, expands sentences, synthesizes speech.
- The child experiences the *output* of AI, not the complexity.

**3. Privacy is non-negotiable**
- User data lives in SwiftData + iCloud (private to the user's Apple ecosystem).
- No backend servers. No analytics platforms. No data harvesting.
- API calls to AI services (OpenAI) are stateless - send words, get sentences/speech back. No user identity or history stored externally.
- This population is vulnerable. Trust is everything.

**4. Open source (Apache)**
- Give this back to the community.
- Enable others to build on it, adapt it, translate it.

---

### Architecture Overview

#### Data Layer (Private - SwiftData + iCloud)
- Tile sets, tiles, layouts, scenes
- Usage history and analytics (on-device only)
- User preferences, voice settings
- Therapist-created content
- Syncs across user's own devices via iCloud. Nothing else.

#### Intelligence Layer (Stateless API Calls)
- **Sentence expansion**: Child selects tiles ("eat" + "chocolate") -> API constructs natural sentence ("I want to eat some chocolate")
- **Text-to-speech**: High quality, multiple voices (OpenAI TTS or similar). Voice selection matters - child may want a kid-sounding voice that feels like "theirs"
- **AI-assisted tile set generation**: Therapist describes a goal ("emotions for a 5-year-old working on frustration vs anger") -> AI generates vocabulary, categories, suggested layout
- API provider: OpenAI (current target). Architecture should allow swapping providers.

---

### Two-Layer UX

#### Layer 1: Child Surface
- Full-screen tile grid. Big, clear, high-contrast.
- Sentence bar at top showing selected words.
- "Speak" button to trigger sentence expansion + TTS.
- Category pages (food, feelings, people, actions, places, etc.)
- Promoted tiles: Frequently used combinations ("eat chocolate") can be promoted to their own single tile. Emerges from the child's own usage patterns.

#### Layer 2: Therapist/Parent Surface
- Behind Face ID / passcode authentication.
- **Create/edit tile sets**: Build custom vocabularies, assign images, set positions.
- **Scenes/Worlds**: Curated communication contexts:
  - Home morning routine
  - Classroom
  - Playground
  - Therapy session (targeted vocabulary)
  - Grandma's house
  - etc.
- **Import/export tile sets**: File-based, AirDrop between devices. No cloud service needed. Therapist builds on their device, AirDrops to child's iPad.
- **Usage analytics**: "This week Jamie used 'frustrated' 12 times but never 'disappointed'. Sentence complexity increased." Data stays on device. Child should never feel surveilled.
- **Session mode**: Therapist takes over the tile set for a focused session (e.g., all about emotions). Reverts to normal home setting afterward.

---

### UX Patterns (from original Blaster)

**Sentence Tray** (top of screen):
- Horizontal strip showing tile images the child has selected (e.g., [mom] [eat] [peanut butter])
- Below the tray: the AI-generated sentence text ("Mom, I want to eat peanut butter.")
- Clear button (X) to reset the tray

**Tile Grid** (main area):
- Dense grid of tiles filling the iPad screen. Each tile = image + label text below.
- Tiles are either **audible** (tap adds to sentence tray) or **navigation** (tap jumps to another page)
- Some tiles are BOTH (e.g., "eat" is audible AND links to the eat page full of food items)
- Navigation tiles include: home, next_page, previous_page, and category headers
- Grid is paginated when a category has too many items (actions spans 2 pages with next/prev navigation)

**Page Navigation Structure:**
- Home page: category navigation tiles (people, actions, social, places, etc.) + frequently used people (mom, dad, grandma, etc.)
- Category pages: "eat" page has all food (meals, fruit, veggies, snacks in one big page), "drink" page, "actions" page (paginated), "social" page, "people" page
- Cross-links between related pages (eat page has link to drink page and vice versa)

**Sentence Cache:**
- AI-generated sentences are cached by tile combination key (e.g., "mom, eat" or "eat, mom, pizza")
- Cache hits avoid redundant API calls - both cost savings and instant response for frequent phrases
- Cache tracks hit count per entry - feeds into promoted tile logic
- Cache view shows: tile combination, cache hits, generated sentence, date, play/delete buttons

**Usage Analytics:**
- Per-tile metrics: selected count, used count, cache hits
- Overview shows "Frequently Used Tiles" ranked by usage
- "Top Cache Entries" shows most common phrases
- This data drives the promoted tile feature - high-frequency combinations become single tiles

---

### Data Model (Sketch)

Informed by the original Blaster models but evolved for the next-gen architecture:

**Core concept**: Tiles exist in a global vocabulary. Pages reference tiles and give them position, navigation behavior, and audibility. This separation means the same tile ("eat") can appear on multiple pages with different behaviors.

```
TileModel (the vocabulary unit)
  - key: String (unique ID, doubles as image asset name)
  - displayName: String (shown on tile)
  - value: String (the word/phrase value)
  - wordClass: String (category: food, actions, people, etc.)
  - bundleImage: String (asset name for bundled image)
  - userImageData: Data? (optional user-provided photo)
  - metrics: [MetricType: Metric] (selected, used, cache hits, etc.)
  - type: TileType (word vs phrase - for promoted combo tiles)

PageModel (an ordered page of tiles)
  - displayName: String
  - tiles: [PageTileModel] (relationship)
  - tileOrder: [String] (explicit ordering array)
  - orderedTiles: computed from tileOrder

PageTileModel (junction: tile + page-specific behavior)
  - tile: TileModel (relationship)
  - link: String (if non-empty, tapping navigates to this page key)
  - isAudible: Bool (if true, tapping adds to sentence tray)

SentenceCache (cached AI responses)
  - tileKeys: [String] (the combination, e.g., ["mom", "eat", "pizza"])
  - sentence: String ("Mom, I want to eat pizza.")
  - hitCount: Int
  - created/lastUsed: Date

Scene (future: context switching)
  - name, description
  - activePages: [PageModel]
  - isActive: Bool
```

**Key relationships:**
- A Tile can appear on many Pages (via PageTileModel junction)
- A Page owns an ordered list of PageTileModels
- The same tile can be audible on one page and navigation-only on another
- Scenes compose Pages into a communication context
- **wordClass is purely semantic metadata** - it describes what a tile IS (noun, verb, feeling, etc.), NOT where it appears. Page membership is entirely a layout/composition decision. A therapist can compose pages from any mix of wordClasses based on therapeutic intent (e.g., an "emotions" page pulling from describe, actions, and social tiles).

---

### Tile Images / Symbols

The original Blaster uses custom illustrated images per vocabulary word (the key doubles as the asset name). For next gen:
- **Default**: Ship with the original illustrated image set (or similar open-source AAC symbols)
- **Customization**: Support user photos (camera/photo library) per tile - the child's actual dog, their real kitchen, their friend's face
- **AI-generated**: For therapist-created tile sets, AI could generate appropriate images
- **SF Symbols**: Could supplement for abstract/action concepts

---

### Sentence Engine

**Interaction flow:**
1. Child taps tiles → added to sentence tray (tap again to remove)
2. 1-second debounce: after no taps for ~1 second, trigger sentence generation
3. Cache check first → instant response + audio playback on cache hit
4. Cache miss → API call to OpenAI
5. Staleness guard: when API response arrives, verify selection hasn't changed while waiting. If child kept tapping, cache the result but don't display it (it's stale)
6. Display generated sentence text below tray + play audio

**No "speak" button.** The system auto-generates once the child pauses. This keeps the interaction dead simple - just tap tiles.

**Single tile:** If only one tile is selected, just display the word (no API call). Configurable option for auto-voicing single words.

**Max selected tiles:** Currently 4 in original. Should be configurable per child/profile.

**System prompt design (from original, to evolve):**
- Persona: "You are their voice and soul"
- Explains the word-selection communication model
- Safety rails: no sexual/violent content generation
- Uses wordClass as disambiguation context - tiles are sent as `"mom (people), eat (actions), pizza (meals)"` so AI can interpret ambiguous words correctly (e.g., "snack bar (food)" vs "snack bar (place)")
- Age/voice setting: "grammar and vocabulary of a 1st grade student" → should be configurable per child profile in next gen
- The prompt encourages relatable first-person sentences: "mom, tired" → "Mom, I am tired. Can I go lie down?"

**API integration:**
- Provider: OpenAI (target: gpt-4o-audio-preview for integrated text+audio response)
- Single API call returns both text transcript and base64 audio
- Voice: configurable (original hardcoded "nova"). Child should be able to pick "their" voice
- Architecture should abstract the provider so it can be swapped

**Sentence cache (SwiftData):**
- Key: sorted tile combination (e.g., "eat, mom, pizza")
- Value: generated sentence text + base64 audio data
- Hit count tracking (feeds promoted tile logic)
- Cache lookup avoids API cost + gives instant response for repeated phrases
- The cache IS the child's developing language - their most common expressions crystallize into instant, cached phrases

**Conversational context:**
- Sentence generation should NOT be stateless. The session should track recent generated sentences and feed them back to the AI as conversation history.
- E.g., child says "Mom, I'm hungry" then taps "eat" + "pizza" → AI generates "Can I have pizza?" instead of the standalone "I want to eat pizza" (because the hunger context was just established)
- This makes the generated language feel like a real conversation, not a series of isolated announcements.

**Repetition as intensity / emotional escalation:**
- When the child taps the same tile combination repeatedly, each repetition should escalate the emotional intensity of the generated sentence.
- Real example: "pinkfong video" tapped once → "Grandpa, can we watch some Pinkfong videos?"
- Tapped 3 times → "Grandpa, I really want to watch Pinkfong right now!"
- Tapped 10 times → "GRANDPA, ALL I WANT TO DO IS WATCH PINKFONG NOW!"
- This is critical: repetition IS the child's volume knob. Neurotypical kids whine, raise their voice, tug on sleeves. A non-verbal child has tile taps. The device must understand that repetition = urgency/insistence and reflect it in both the language AND the speech (tone, emphasis, volume).
- Implementation: track repetition count in the session context. Feed it to the prompt as an intensity signal. Don't cache escalated sentences the same way - the cache should serve the baseline version, and escalation is applied dynamically.
- The TTS voice/prosody should also reflect the escalation - louder, more emphatic delivery as repetitions increase.

**Implementation notes for next gen:**
- Replace custom ApiTimer with Swift concurrency (`Task` + cancellation for debounce)
- Cache should persist in SwiftData (syncs via iCloud across devices)
- Cache serves the baseline sentence; conversational context and repetition escalation are layered on top dynamically (cache miss path)

---

### v1 Build Priorities (Proposed)

1. **Core grid UI** - iPad-first tile grid, sentence bar, speak button
2. **Default tile set** - The ~500 word vocabulary, organized into categories
3. **Sentence engine** - OpenAI API integration for sentence expansion
4. **TTS** - OpenAI TTS integration, voice selection
5. **SwiftData models** - TileSet/Tile/Scene architecture (even if v1 only uses defaults)
6. **Therapist mode** - Face ID gate, create/edit tile sets, swap active sets
7. **Promoted tiles** - Usage tracking, surfacing frequent combinations
8. **Scenes** - Context switching between communication environments
9. **AI tile set generator** - Therapist describes goal, AI builds the tile set
10. **Import/export** - AirDrop / file sharing of tile sets

---

### Platform
- iPad primary
- iOS/iPadOS, SwiftUI, SwiftData
- iPhone companion possible later
- Target: iOS 26+

---

### Default Vocabulary Structure (from original Blaster)

~500 words across these wordClass categories:
- **navigation**: home, next_page, previous_page
- **actions**: ~90 verbs (eat, drink, play, want, help, go, stop, feel, etc.)
- **social**: greetings, responses, common phrases (hello, goodbye, yes, no, please, thank you, i_love_you, etc.)
- **people**: family, pronouns (mom, dad, grandma, friend, teacher, she, they, etc.)
- **food/drinks/snacks/meals/fruit/veggie**: comprehensive food vocabulary
- **places**: home rooms, community locations, school areas
- **describe**: ~90 adjectives/adverbs (big, little, happy, sad, fast, slow, etc.)
- **colors**: 14 colors
- **body/health**: body parts, ailments
- **toy/sports/games/art**: play and activity items
- **weather/shape**: environmental and educational concepts

Page structure: Home -> category pages -> sub-pages (with pagination for large categories)

---

### Decisions Made

**Tile/Page sharing format:**
- Define a JSON grammar for tiles, pages, and tile sets. Portable, human-readable.
- Sharing works via multiple channels: host JSON on a website (URL import), text/message the JSON (iOS share sheet / universal links), AirDrop the file.
- App registers as a handler for the JSON format - opening/receiving it triggers import flow.
- This supports both ad-hoc sharing (therapist texts a tile set to a parent) AND structured publishing (curated tile sets hosted on a website).
- Privacy preserved: the JSON contains vocabulary/layout only, never usage data or personal info.

**Age/profile influences the AI layer:**
- Age is a per-child profile setting.
- It determines: sentence complexity, vocabulary level in generated sentences, TTS voice selection/characteristics.
- A 4-year-old gets simpler sentences and a younger-sounding voice. A 12-year-old gets more complex language.
- This feeds directly into the system prompt ("communicate at the level of a [age]-year-old").

**API key management:**
- User supplies their own API keys during setup/configuration.
- Best practices TBD - need to research secure key storage on iOS (Keychain), onboarding UX for non-technical parents.
- OpenAI is the target provider. Relationship exists to influence what we need from them if gaps emerge.

---

### Open Questions
- Voice selection: What voices feel right for a child? Can we let the child pick "their" voice?
- Accessibility: Beyond AAC - VoiceOver, Switch Control, other iOS accessibility features?
- Localization: Multi-language support from the start or later?
- Image assets: Source/license for the default tile images? Use original Blaster images or find open-source AAC symbol set?
- Sentence cache: Should cache be per-scene or global? What's the eviction strategy?
- JSON sharing format: What's the schema? Define early so it's stable for third-party tile set creators.
- Onboarding: How does a non-technical parent/guardian set up API keys without friction?
