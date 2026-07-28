# Build Plan

Working checklist. Companion to `PRD.md` and `Tokens.swift`.

**Core sequencing principle: build the ugly version of the core loop first.**
Create → seal → wait → unlock, with zero styling. The lock lifecycle is where being wrong is expensive and invisible; the scrapbook layer is where you'll spend the most *time*. Get the machine working, then make it beautiful. Do not style anything until the loop works end to end.

---

## Step 0 — Setup (~30 min, before opening Claude Code)

- [ ] **Commit your current state.** Whatever it is. You want a known-good point to return to.
- [ ] **Create a working branch** — `git checkout -b rebuild`
- [ ] Put `PRD.md` in the repo at **`docs/PRD.md`** (in the repo, so Claude Code can read it — not on your desktop)
- [ ] Put `Tokens.swift` in the source tree
- [ ] **Bump the deployment target to iOS 26.0** in Xcode → project settings
- [ ] Confirm the project still builds

---

## Step 1 — Audit (1 session)

Don't build anything. Find out what you actually have.

> Read `docs/PRD.md`, then audit this codebase and report back. Don't write any code yet.
>
> 1. What exists? Give me a file-by-file inventory of what's implemented vs. stubbed.
> 2. **How are postcards currently persisted?** §9 claims no persistence layer was chosen, but the app apparently creates postcards, so something must be storing them. Find out what.
> 3. Which of the four bugs in §5.1 actually reproduce?
> 4. §4 treats all view code as disposable. Given that, what's worth keeping and what should be deleted?
> 5. What in §9 is wrong?

- [ ] Run it
- [ ] **Update §9 of the PRD with what's actually true**
- [ ] Decide: evolve this repo, or start fresh and port the good parts?

---

## Step 2 — Foundation (2–3 sessions, no UI)

Pure logic, fully testable, nothing visual. This is the part that must be correct.

**2a. Bundle format**
> Read §6.2. Implement the postcard bundle format as Swift `Codable` types, with encode/decode to the directory structure described. Write unit tests proving round-trip fidelity — a Postcard encoded and decoded back must be identical, including decoration positions, rotations, and z-order. No UI.

**2b. Data layer**
> Read §3 and §6.1. Implement SwiftData models for Postcard and DesignPreset behind a `PostcardStore` protocol. Follow the CloudKit-compatibility rules in §3 exactly: every property optional or defaulted, no unique constraints, no required relationships. Include an in-memory implementation for tests.

**2c. Lock lifecycle + trusted time**
> Read §5.3 and §5.4. Implement the lock state machine and a `TrustedClock`. Unit tests must cover: edit-window truncation when the unlock date arrives first; clock tampering (moving device time forward must NOT unlock a card); offline reboot (uptime reset must keep the card locked).

- [ ] All three merged with passing tests

---

## Step 3 — Ugly core loop (3–5 sessions)

System fonts, grey rectangles, no textures. **Resist styling anything.**

- [ ] Composer: multi-photo select, carousel, reorder, title, description, unlock date (§5.1)
- [ ] Fix the four known composer bugs
- [ ] Timeline: list of cards, locked ones blurred (§5.5)
- [ ] Display view + fix the top-bar bug (§5.6)
- [ ] Delete with confirmation (§5.3)
- [ ] Local notifications, including permission-denied path and **re-scheduling on every launch** (§5.7)

**🚩 Milestone:** seal a card for tomorrow, change nothing, wait a day. Does it unlock and notify correctly? **If not, stop and fix it before doing anything else.**

---

## Step 4 — Make it good (5–8 sessions)

Now the look. Assets should already be in hand from the parallel track below.

- [ ] Wire `Tokens.swift` through every existing view — delete all hard-coded values
- [ ] Custom chrome, replacing system nav bars (§4.5)
- [ ] Scrapbook canvas: substrates, tape, stickers, torn edges (§4.2)
- [ ] Direct manipulation (§5.2) — **expect this to be the hardest session; UIKit fallback is fine**
- [ ] Flatten-on-seal + thumbnail caching (§4.4)
- [ ] Motion pass: `matchedGeometryEffect`, spring transitions (§4.5)
- [ ] Dark mode — chrome only
- [ ] **Performance test on a real device** with 50 maxed-out cards

---

## Step 5 — Ship prep

- [ ] Bundle export UI (§5.8) — the only backup path before sync
- [ ] Empty state, error states (§7.2)
- [ ] Accessibility pass: Dynamic Type, VoiceOver labels
- [ ] Simple tutorial (§5.9)
- [ ] **Pay the $99** — needed for TestFlight
- [ ] TestFlight build, crash reporting on
- [ ] App Store prerequisites (PRD §12 → Post-build)

---

## Parallel track — start today

**Assets are the long pole.** Nothing in Steps 1–3 needs them, but Step 4 stops dead without them. Start now.

- [ ] 3 paper substrates (kraft, cream cardstock, lined/ledger)
- [ ] 3 tape pieces — **shadows pre-baked into the PNG** (§4.4)
- [ ] 6 stickers / ephemera
- [ ] 2–3 torn edge masks
- [ ] App icon
- [ ] Pick and license fonts — prefer SIL OFL (Google Fonts)

Sources: make them yourself · Creative Market / Etsy digital scrapbook kits · commission on Fiverr. **Check commercial-use licensing on anything you buy.**

---

## Working with Claude Code

- **One task per session.** Verify it works, commit, then start the next.
- **Reference sections by number** — "implement §5.2" beats describing it again.
- **Never say "build the composer."** Say "implement the photo carousel with drag-to-reorder per §5.1."
- **Commit before each session.** Easy revert when a session goes sideways.
- **When it's wrong, revert and re-prompt** rather than patching on top of a bad start.
- Free-account provisioning profiles expire after 7 days — **re-sign weekly** to keep testing on your own device.
- Test on a **real device** early. Simulator lies about performance and can't do haptics.

---

## Rough shape

| Phase | Sessions |
|---|---|
| Audit | 1 |
| Foundation | 2–3 |
| Ugly core loop | 3–5 |
| Make it good | 5–8 |
| Ship prep | 3–4 |

**~15–20 productive sessions to a TestFlight build.** Step 4 will take longer than you expect; Step 2 will take less.
