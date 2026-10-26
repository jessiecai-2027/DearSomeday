# Postcard Capsule — Project Requirements

> **Working title.** Final name TBD — don't bake it into bundle IDs, asset names, or branding.

**v2.1** · 2026-07-28 · supersedes all prior drafts
**Companion file:** `Tokens.swift` — the source of truth for all design values

---

## 1. Product

Photo postcards addressed to your future self. Compose a card, pick an unlock date, and it seals — appearing blurred on your timeline until that date arrives, when a notification delivers it back to you.

**The promise:** the delight of a forgotten message from your past self, in a warm, tactile interface.

**Trust contract:** sealed cards must never be lost or revealed early. Everything else is negotiable; this isn't.

**Non-goals:** sending to other people · social feed · Android/web in v1 · cross-platform frameworks.

---

## 2. v1 Scope

**Scope is the primary risk on this project.** This table is the contract — anything absent is out.

| Area | v1 includes |
|---|---|
| **Create** | Multi-photo select, carousel, reorder, title, description, unlock date |
| **Decorate** | Small first-party asset set, direct manipulation (§5.2), undo/redo |
| **Timeline** | Compact + card views, locked cards blurred, delete with confirmation |
| **Lifecycle** | Seal → 1-week edit window → trusted-time unlock |
| **Notify** | Local push on unlock, permission-denied fallback |
| **Export** | Styled card → Photos; postcard bundle → backup |
| **Storage** | Local SwiftData. **No account, no auth, no sync** |
| **Design** | Custom chrome, scrapbook canvas, light + dark mode |

**v1.1:** CloudKit sync · Sign in with Apple · bundle import
**Later:** in-app camera · voice memos · expanded asset packs · first-run tutorial · monetization
**Cut:** pixel pet + streaks · random/unscheduled release · ads · SMS · email reminders · multi-login

---

## 3. Platform

| | |
|---|---|
| Target | iPhone, iOS 26.0 minimum, portrait |
| Framework | Native SwiftUI |
| Chrome | **Custom throughout — no system nav/tab bars** (§4.5) |
| Storage | **Phase 1:** local SwiftData · **Phase 2 (v1.1):** CloudKit sync |
| Auth | None in v1 · Sign in with Apple in v1.1 |
| iPad | Runs scaled, not optimised |
| Localisation | English only |
| Cost | $0 recurring. Only fixed cost is Apple Developer Program, $99/yr — **currently unpaid** |

### Phased storage

A free Apple ID supports local notifications, camera, photo picker, and all UI. It **cannot** create a CloudKit container or enable Sign in with Apple. Hence Phase 1 ships local-only.

**SwiftData model rules — follow from the first commit**, or Phase 2 becomes a migration:
- Every property optional or with a default value
- No unique constraints
- No required (non-optional) relationships

Keep all persistence behind a `PostcardStore` protocol so Phase 2 is an implementation swap.

**v1 consequence:** no live sync. Device backups do include the SwiftData store (don't mark it excluded), so restore-to-new-phone works — but bundle export is the user's only self-directed backup until v1.1.

---

## 4. Design System

**Art direction: mixed media / scrapbook.** Layered paper, tape, torn edges, collage, handwriting mixed with print.

### 4.1 Governing rule — minimal chrome, maximal canvas

The scrapbook aesthetic and the "minimal, uncluttered" requirement are resolved by separating the two surfaces:

| Surface | Treatment |
|---|---|
| **Chrome** — timeline, nav, settings, dialogs | Quiet, spare, generous whitespace, minimal ornament |
| **Canvas** — the postcard, composer, display view | All texture, layering, collage, density |

The interface is the desk. The postcard is the thing on it. **Check every design decision against which surface it belongs to.**

### 4.2 Scrapbook vocabulary

- **Substrates** — kraft, cardstock, vellum, graph, ledger, aged newsprint
- **Fasteners** — washi tape, masking tape, photo corners, staples, paperclips, stitching
- **Edges** — torn, deckled, scalloped. **Not uniform corner radii**
- **Ephemera** — stamps, postmarks, ticket stubs, luggage tags, doodles
- **Layering** — elements overlap and occlude; physical offset shadows, not flat elevation
- **Imperfection** — elements sit at ±3° rotation. Nothing perfectly square. *This detail does most of the work*
- **Type mixing** — handwriting + typewriter + printed label on one card

Photo framing varies by type (photo corners, taped, torn-edge, polaroid) rather than one rounded rectangle. The postcard is the substrate; polaroid is one framing option.

### 4.3 Tokens

**Palette — locked**

| Token | Hex | Role |
|---|---|---|
| `paper.cream` | `#F3E4C9` | Primary substrate |
| `paper.tan` | `#BFA28C` | Secondary substrate, tape, aged edges |
| `paper.taupe` | `#A98B76` | Deep accent, postmarks, borders |
| `accent.sage` | `#BABF94` | Contrast accent, stamps, botanicals |
| `ink.espresso` | `#2B241E` | **All text** |

The four surface colours are mid-to-light tones and fail WCAG AA against each other — taupe on cream is only **2.52:1**. `ink.espresso` passes everywhere: **12.19:1** on cream, **7.98:1** on sage, **6.38:1** on tan, **4.83:1** on taupe. **Surface colours are never used for text.**

**Dark mode: darken the desk, not the paper.** The postcard stays bright cream in both appearances; only the surrounding chrome goes deep brown. Physically it's a scrapbook on a desk at night. Darkening aged paper textures makes them muddy and would require a second asset set — this needs none, and it makes the card a glowing object of attention. **Only chrome tokens have dark variants; canvas tokens are fixed.**

**All other tokens live in `Tokens.swift`** — type scale, spacing, radii, shadows, canvas behaviour, motion. Never hard-code a design value in a view.

Three choices in that file are deliberate and shouldn't be "corrected":

| Choice | Why |
|---|---|
| **Shadows derive from `ink.espresso`, never black** | Neutral grey against a warm palette reads as dirty. Most commonly gotten wrong |
| **Screen margins are 24, not the iOS-standard 16** | "Minimal chrome" is achieved mostly through whitespace. This single value does more for it than any other |
| **Corner radii are tighter than current iOS fashion** | Paper is cut or torn, not soft and blobby. Rounded chrome fights the material story |

Canvas type is sized **up** — handwriting and display faces have smaller x-heights, so 20pt handwriting reads like 16pt system. Canvas leading is looser than chrome; grain competes with tight lines.

**Highest-impact single value:** `Canvas.placementJitter` (±2.5°). It's what makes a card look arranged by hand rather than laid out by a computer.

**Still open:** font families (§4.6) — placeholders in `Tokens.swift` fall back to system so the app builds today.

### 4.4 Layering & performance

**The cost driver is runtime `.shadow()` on complex alpha shapes** — the system derives shadow geometry from the alpha channel every frame. Fifty torn-paper elements in a scrolling timeline is what drops frames, not layering itself.

1. **Flatten on seal.** Sealed cards are immutable — composite layers once into a cached bitmap. Timeline renders flat images at zero layering cost.
2. **Pre-bake shadows into assets.** Ship paper, tape, and stamps as PNGs with shadows already painted in. **Never use runtime `.shadow()` on the canvas.**
3. **Two render paths.** Edit = live layers (one card on screen). Display = flat cached image. Never use the live path in a scrolling list.
4. **Cache thumbnails per view mode.** Compact ≈300px, card view larger. Invalidate on edit.
5. **`LazyVStack` + 20-element cap per card.**

Apply film grain **once at the top level**, never per element.

**Test scroll performance in week two** against a deliberately maxed-out card.

### 4.5 Motion — Liquid Glass *feel*, not *material*

Translucency, refraction, and blur-behind fight the art direction — glass over paper reads as two apps arguing. **Take the motion, reject the material.**

Apps built with Xcode 26 auto-adopt Liquid Glass on system components. The `UIDesignRequiresCompatibility` opt-out **is being removed in Xcode 27** — don't build on it. **Use custom chrome**, and system glass never applies.

| Quality | Implementation |
|---|---|
| Morph, don't cut | `matchedGeometryEffect` — card expands into detail, not a screen push |
| Interruptible springs | `.snappy`, `.smooth`, `.bouncy`. **Never** `.linear` or fixed-duration `.easeInOut` |
| Gesture-tracked, not triggered | Animation follows the finger continuously. *Biggest contributor to "fluid"* |
| Depth | Parallax and scale, not hard z-cuts |
| Entry/exit | `.scrollTransition` |

**Forbidden:** translucent materials, backdrop blur, refraction, specular highlights.

### 4.6 Typography & assets

Chrome uses the system font (Dynamic Type comes free). Canvas uses handwriting, typewriter, and retro display faces.

**Open:** font licensing — embedded fonts need redistribution rights. Google Fonts (SIL OFL) avoids this.

**⚠️ Largest unowned dependency:** substrates, tape, stamps, edge masks, ephemera, app icon. Not sourced. Scope v1 tightly — 3 substrates, 3 tapes, 6 stickers.

---

## 5. Functional Requirements

### 5.1 Composer

- Multi-photo select (Instagram-style), swipeable carousel, drag to reorder
- Photo count indicator, top-right
- **Max 10 photos**, all at **4:5 portrait**, filling the frame — requires a crop/reposition UI
- Title (**60 char max**) and description (**2,000 char max**)
- Description is a **fixed-height scrollable box** — must not grow infinitely
- Keyboard dismissible from the description field
- Empty title, empty description, and **zero-photo (text-only) cards are all permitted**
- Title bar styling matches the timeline title bar
- Decoration: substrate, tape, stickers, stamps, retro fonts, colour pickers
- Save decorated cards as reusable design presets

**Known bugs in the current base:** duplicate photos in picker/carousel · description box grows infinitely · keyboard trap in description · title bar mismatch.

### 5.2 Canvas direct manipulation

Composer only — sealed cards are immutable, so this path never has more than one card on screen.

1. **One unified transform gesture** — drag, pinch-scale, two-finger rotate act **simultaneously** on the selected element. Splitting into modes destroys the feel
2. **Spring lag on tracking** — pixel-glued tracking feels dead
3. **Snapping with haptics** — canvas centre, edges, 0/90/180/270°. Light `UIImpactFeedbackGenerator` on snap
4. **Selection** — tap to select (corner handles), tap outside to deselect
5. **Drag-to-delete** — trash zone fades in during drag
6. **Long-press to bring to front**
7. **Bounds constraint** — can't drag fully off-canvas
8. **Undo/redo** — non-negotiable

Per-element state: `position`, `rotation`, `scale`, `zIndex`. `@GestureState` in flight, commit on `.onEnded`.

**⚠️ SwiftUI's `simultaneousGesture` is unreliable combining drag + magnify + rotate.** Wrapping UIKit gesture recognizers in a `UIViewRepresentable` is the accepted fallback — **don't burn multiple sessions fighting pure SwiftUI here.**

### 5.3 Lock lifecycle

1. Compose → choose unlock date → seal
2. Sealed cards appear **blurred**: no photos, no description. **Title remains visible** (notifications reference it)
3. **Editable for 1 week after creation, all users.** Window **truncates** if the unlock date arrives first
4. **Deletion permitted at any time, including while locked** — but contents are never shown before deletion
5. On unlock: card opens, notifies, becomes permanently readable. **Prior edit versions are purged**; only the final card is retained

**Deletion UX:** confirmation required. For locked cards the dialog shows **title and unlock date** and states plainly: *"You won't be able to see what's inside first. This can't be undone."* Recommend hold-to-confirm for locked cards. No recovery bin.

**Unlock dates are stored as absolute instants (UTC)**, never wall-clock local.

### 5.4 Trusted time

Unlock is **never** evaluated against the device clock.

```
On launch/foreground:
    serverNow      ← Date header from an HTTPS response
    lastTrustedTime = serverNow
    uptimeAtSync    = ProcessInfo.processInfo.systemUptime

Evaluate lock:
    trustedNow = lastTrustedTime + (systemUptime − uptimeAtSync)
    unlocked   = trustedNow >= unlockDate
```

`systemUptime` is monotonic and not user-settable. It resets on reboot — if the device reboots offline and cached time hasn't reached the unlock date, the card **stays locked** with a quiet waiting state. Never fall back to device time.

**⚠️ iOS schedules local notifications against *device* time**, so a spoofed clock fires them early regardless. Therefore: notification bodies carry **the title at most**, and the app **re-verifies trusted time on open** before revealing anything.

**Proportionality:** the person being locked out asked to be locked out. This is a diary lock, not adversarial security. Don't build key escrow on top of it.

### 5.5 Timeline

- Two modes: **compact** and **card view**
- **Sort:** sealed first, soonest unlock at top; unlocked below, most recent first
- Locked cards blurred, title visible
- Delete on every card, confirmation required
- **Empty state:** single illustrated prompt + one create button. No tutorial content
- Lazy load in batches of **50**

### 5.6 Display

**Known bug:** the white top bar fails to disappear cleanly while scrolling a postcard. Pick one — pin it permanently or remove it entirely. Don't leave it half-animating.

### 5.7 Notifications

- Local push on unlock: banner **and** Notification Center entry, referencing the title
- **Delivery at 9:00am in the user's current time zone**
- Remove the debug "test notification" button before release
- If permission is denied: card still unlocks silently, surface an in-app badge

**⚠️ Uninstall destroys the pending notification queue.** With no sync in v1, a reinstall leaves cards intact via device backup but nothing will ever fire. **Re-scan all sealed cards and re-schedule on every launch.**

### 5.8 Photo capture & export

- Import from Camera Roll (P0)
- One-tap export of the finished card → Photos, **PNG at 2× card render size**
- Bundle export for backup (§6.2)
- In-app camera with film shutter and date stamp — later

### 5.9 Onboarding

Deferred. A simple tutorial, built **after** the app is functional — designing it before the interface exists means documenting screens that don't exist. Must be skippable and re-openable from settings.

### 5.10 Monetization

None in v1. Standing constraints when revisited: **never paywall postcard count · no ads · no third-party tracking.**

---

## 6. Data

### 6.1 Model

```
Postcard
  id (own UUID, never a platform record ID)
  schemaVersion
  title, description
  photos: [PhotoRef]              // ordered
  unlockDate (UTC instant), createdAt, editableUntil
  state: draft | sealed | unlocked
  substrateId
  decorationElements: [DecorationElement]

DesignPreset
  id, name, substrateId, fontId, colorSet, decorationElements
```

**Photo storage:** display-resolution derivatives — longest edge 2048px, JPEG q0.8. Originals not retained.

### 6.2 Portable bundle format

Specify **before** writing storage code. Enables export/import and keeps any future Android app compatible without sharing code.

```
postcard-<uuid>.bundle/
├── manifest.json
└── photos/01.jpg, 02.jpg, …
```

```json
{
  "schemaVersion": 1,
  "id": "uuid",
  "title": "string",
  "description": "string",
  "createdAt": "ISO-8601",
  "editableUntil": "ISO-8601",
  "unlockDate": "ISO-8601",
  "state": "sealed | unlocked",
  "photos": [{ "file": "photos/01.jpg", "order": 0 }],
  "decoration": {
    "substrateId": "kraft-01",
    "elements": [{
      "id": "uuid",
      "type": "sticker | tape | stamp | text | photoFrame",
      "assetId": "washi-03",
      "position": { "x": 0.42, "y": 0.18 },
      "rotation": -2.5,
      "scale": 1.0,
      "zIndex": 3,
      "text": null,
      "fontId": null
    }]
  }
}
```

Positions are **normalised 0–1** relative to card bounds. `zIndex` determines paint order.

---

## 7. Permissions, Errors & Edge Cases

### 7.1 Permissions

**When you ask determines whether people grant.** Never request at launch.

| Permission | Ask when | Priming |
|---|---|---|
| Photo library | First tap of "add photos" | None — intent is obvious |
| Notifications | Immediately after sealing the **first** card | One screen: *"we'll tell you when this opens"* |
| Camera | First tap of in-app camera (later) | None |

Prefer **limited** photo access where offered.

### 7.2 Error states

| Condition | Behaviour |
|---|---|
| Notifications denied | Unlock silently, in-app badge, link to Settings. **Never nag** |
| Photo access denied | Explain, link to Settings, keep composer usable for text-only cards |
| Device storage full | Fail gracefully, keep draft in memory, say so plainly |
| iCloud quota full (v1.1) | Non-blaming copy. Local data fine, only sync paused |
| Corrupt bundle on import | Reject with a specific reason. **Never partially import** |
| Trusted time unreachable | Stay locked, quiet waiting state |

---

## 8. Non-Functional

| Area | Requirement |
|---|---|
| Performance | 60fps timeline scroll with 200+ cards; no perceptible transition lag |
| Accessibility | Dynamic Type · VoiceOver labels on all interactive elements · 4.5:1 text contrast |
| Data integrity | Sealed cards never lost or prematurely revealed. **The trust contract** |
| Privacy | No ads, no third-party tracking. Contents never leave the device in v1 |
| Testing | Bundle round-trip · lock state machine · trusted-time logic (tampering, offline reboot). **No UI tests** — not worth the maintenance |
| Crash visibility | TestFlight crash reports from the first beta build. No third-party analytics |

---

## 9. Current Build Status

**A working base exists.**

- ✅ Functioning iOS codebase with core scaffolding
- ⚠️ **UI is placeholder quality — treat all view code as disposable.** §4 is a rebuild, not a restyle
- ❌ Most of §5 unimplemented
- ❌ No persistence layer chosen (Firebase was never set up)
- 🐛 Known bugs in §5.1, §5.6, §5.7

**⚠️ These claims are secondhand and unverified.** One doesn't add up: "no persistence layer" — yet a working app that creates postcards must store them *somehow* (`UserDefaults`? in-memory? Core Data?). That unknown sits directly beneath build-order step 2.

**Make the first session an audit, not a build:**

> *Inventory this codebase. What exists? How are postcards currently persisted? Which of the four bugs in §5.1 reproduce? Given §4 treats view code as disposable, what's worth keeping?*

Then update this section with what's actually true.

**For implementers:** existing *logic and structure* may be worth keeping; existing *views* should not be assumed correct. Ask before preserving a view.

---

## 10. Build Order

0. **Audit the existing codebase** (§9) — before planning anything else
1. **Specify the bundle format** (§6.2) — before any storage code
2. **SwiftData persistence** behind `PostcardStore`, following the §3 CloudKit-compatibility rules
3. **Fix the four known composer bugs** (§5.1)
4. **Lock lifecycle + trusted time** (§5.3, §5.4)
5. **Multi-photo carousel, reorder, crop UI** (§5.1)
6. **Direct manipulation** (§5.2)
7. **Timeline view modes + deletion** (§5.5)
8. **Local notifications** including permission-denied and re-scheduling (§5.7)
9. **Decoration toolkit** (§5.1)
10. **Export** (§5.8)

**Don't hand over this whole document and say "build it."** Bounded tasks with verifiable end states work far better — *"implement the bundle format per §6.2 with round-trip encode/decode tests"* is a good task; *"build the composer"* is not.

---

## 11. Android — if it ever happens

**A separate native app, not a migration.** Demand-gated: don't build until people ask.

Storage is free on both platforms because each bills the user's own cloud quota: **iOS → CloudKit**, **Android → Google Drive `appDataFolder`** (a hidden per-app folder charged to the user's Drive, not the developer's). Auth is native on each side.

The shared artifact is **the bundle format (§6.2)**, not code — it gives platform-switchers an export/import path and keeps the two apps honest about parity.

**Real cost is maintenance:** two codebases, every bug fixed twice. This is what kills solo projects, not architecture. If it happens, Kotlin Multiplatform for shared business logic (lock lifecycle, trusted time, bundle parsing) is worth evaluating.

---

## 12. Open Items

### Before coding

- [x] ~~Design tokens~~ — `Tokens.swift`
- [x] ~~Dark mode~~ — darken the chrome, keep the paper bright (§4.3)
- [ ] **Audit the existing codebase** (§9) — verify what's actually there
- [ ] **`CLAUDE.md`** — repo conventions, separate from this document

### Ongoing

- [ ] **Source the v1 asset set** (§4.6) — largest unowned dependency
- [ ] Font licensing (§4.6)
- [ ] Should bundle export UI ship in v1? *(§3 argues yes — only backup path before sync)*
- [ ] Test scroll performance in week two (§4.4)
- [ ] Enable TestFlight crash reporting from first beta (§8)

### Post-build

App Store prerequisites: hosted privacy policy URL · support URL · final app name + availability check · age rating questionnaire · privacy nutrition label · screenshots · app icon · account deletion path (v1.1) · **Apple Developer Program $99, unpaid**.

---

## 13. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Art assets have no owner | High | Scope v1 to a small first-party set; start sourcing now |
| Scope expands and nothing ships | High | §2 is the contract |
| Scrapbook layering vs. 60fps | Medium | §4.4 — flatten on seal, pre-bake shadows |
| SwiftUI gesture composition fights back | Medium | UIKit recognizers via `UIViewRepresentable` (§5.2) |
| Liquid Glass opt-out expires with Xcode 27 | Medium | Custom chrome from day one (§4.5) |
| No sync in v1 — data loss if user never backs up | Medium | Device backup covers most cases; ship bundle export |
| Uninstall silently kills all pending notifications | Medium | Re-schedule on every launch (§5.7) |

---

## 14. Decision Record

Settled decisions, recorded so they aren't relitigated.

| Decision | Rationale |
|---|---|
| **CloudKit, not Firebase** | Firebase Cloud Storage requires the paid Blaze plan (credit card, no spending cap). CloudKit bills the user's iCloud quota — $0 to the developer at any scale |
| **Local SwiftData first, CloudKit in v1.1** | A free Apple ID can't create a CloudKit container |
| **Sign in with Apple only** | CloudKit identity *is* the Apple ID. On an iOS-only app, Google/email logins add methods, not users |
| **Permanent delete, no recovery bin** | A bin that shows nothing is useless; one that shows contents breaks the seal |
| **Native SwiftUI, not React Native/Flutter** | The storage layer can't be shared anyway, and image manipulation is RN's weakest area and this product's core |
| **Android = separate app** | Removes the client-side photo migration problem entirely; CloudKit data can't be exported developer-side |
| **No ads** | Single-digit monthly revenue at this scale, in exchange for an ATT prompt, tracking disclosures, and possible COPPA exposure |
| **No SMS** | The sender pays, not the recipient. US A2P 10DLC costs ~$60 setup + $2–10/month regardless of volume |
| **Motion, not material, from Liquid Glass** | Glass over paper undercuts the art direction |
| **Cut: pixel pet, streaks, random release** | Unscoped art dependencies and unspecified second code paths on non-core features |
