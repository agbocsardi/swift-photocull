# PhotoCull macOS — UX & Visual Design

Native SwiftUI port of the PhotoCull web app (`templates/cull.html`, `static/style.css`,
`static/keys.js`). This document is the authoritative UX reference for the app shell; the
data behaviour it sits on is defined in `docs/CORE-SPEC.md`.

Principles, inherited from the web app and kept on purpose:

- Terminal aesthetic: monospace type, 2 px flat borders, pane numbers, near-zero radii.
- Keyboard-first: every culling action is reachable without the mouse.
- JPG-primary preview, files are the database: no library file, only the `.photocull.json` sidecar.
- The one net-new interaction is **non-destructive cropping**, stored per stem in the sidecar
  (`crops` map) and applied only when exporting JPGs to the dump folder on finalize
  (`CropExportMode.applyCrop`).

One deliberate deviation from the web app: `keys.js` binds `j` = previous / `k` = next
(its own README documents `j` = next). The port uses vim convention everywhere:
**`j` = next, `k` = previous** (and `J` = previous undecided, `K` = next undecided,
exactly as in `keys.js`). One consistent forward/back pair beats preserving a reversed mapping.

---

## 1. Window layout

Single window, default **1280 × 800**, minimum **980 × 640**. Same four numbered panes as
the web app; focus ring still driven by `1`–`4`.

- **Toolbar (48 px, fixed):** `photocull` wordmark (aqua) · session date · `[23/118]` counter ·
  filename · decision badge · spring · `↙ Ingest` button. The HTML header becomes the
  NSWindow toolbar; nothing else moves into it.
- **Sidebar (pane 1, default 320 px, resizable 240–420 px):** sessions list, one row per
  inbox date folder, newest first. Checkbox for multi-finalize selection, date, status badge,
  `undecided/total` plus keep/reject/undecided counts and the `✂ n` crop count.
- **Info pane (pane 3, bottom of sidebar):** auto-height up to 40 % of the sidebar, then
  scrolls. Not user-resizable in v1 — it has at most nine fixed rows, a drag handle would
  be complexity without a payoff.
- **Image pane (pane 2):** all remaining space; letterboxed, neutral `bg0` backdrop.
- **Filmstrip (pane 4, default 120 px, resizable 72–200 px):** horizontal 74 px thumbs,
  current thumb auto-scrolls to centre.
- **Status bar (28 px, fixed):** the key-hint line from the web footer, plus crop/zoom state
  when relevant (`CROP · 3:2` / `160%`).

Resizable: window size, sidebar width, filmstrip height, image zoom. Everything else is fixed.

**Session row anatomy** (44 px tall, full width):

```
┌───────────────────────────────────────────┐
│ ☑  2026-05-14              COMPLETE       │   row 1: checkbox, date (14 bold), status badge
│    10/118   96  12  10   ✂ 3              │   row 2: undecided/total, keep, reject, undecided, crops
└───────────────────────────────────────────┘
```

Active row: `bg3` fill + 3 px purple left bar (web parity). Checkbox column is fixed 24 px;
counts use the same colour coding as the web (`green/red/subtle`). Filter chip (`All`, aqua
outline) and a `✕` clear-selections button sit in the pane header.

**Image loading:** thumbs and preview decode through `ImagePipeline` (`thumbnail` for 74 px
thumbs at ~148 px backing for Retina, `load` with `maxPixel` ≈ viewport size, upsampled at
1:1 zoom by re-decoding at full resolution). `ImageCache` bounds memory; decode happens off
the main actor, current photo first, next photo preloaded — the web app prefetches
`next`, the port does the same with a real cache instead of a `<link rel=prefetch>`.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ photocull · 2026-05-14 · [23/118] · DSCF2771.JPG · (KEEP)            [↙ Ingest] │
├───────────────────────────┬──────────────────────────────────────────────────────┤
│ 1 SESSIONS          All ✕ │ 2 IMAGE                                              │
│ ┌───────────────────────┐ │ ┌──────────────────────────────────────────────────┐ │
│ │☑ 2026-05-14 COMPLETE  │ │ │                                                  │ │
│ │  0/118  96 12 10 ✂ 3  │ │ │              (photo, fit)                        │ │
│ │☑ 2026-05-13 IN PROGR. │ │ │                                                  │ │
│ │  41/96   40  5 15     │ │ │                                                  │ │
│ │  2026-05-09 UNSTARTED │ │ └──────────────────────────────────────────────────┘ │
│ │  0/54                 │ │                                                      │
│ └───────────────────────┘ ├──────────────────────────────────────────────────────┤
│ 3 INFO                    │ 4 FILMSTRIP                                          │
│ Camera  FUJIFILM X-T5     │ ┌────┐┌────┐╔════╗┌────┐┌────┐┌────┐┌────┐┌────┐     │
│ Lens    XF 23mm F1.4      │ │ ✓  ││ ✓  │║▐█▌ ║│ ✗  ││ ·  ││ ✓  ││ ·  ││ ·  │     │
│ ISO     640               │ └────┘└────┘╚════╝└────┘└────┘└────┘└────┘└────┘     │
│ Shutter 1/250s            │   current thumb: aqua ring · red bars = reject ·     │
│ Aperture f/1.4            │   purple top bar = cropped                           │
│ Size    6240×4160         │                                                      │
│ RAW     +RAF              │                                                      │
│ Crop    3:2               │                                                      │
├───────────────────────────┴──────────────────────────────────────────────────────┤
│ ? help · z keep · x reject · j/k next/prev · c crop · f fit · 0 100% · :f fin.  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Crop interaction

Crop is per JPG stem, stored as a normalized `CropRect` (oriented space, top-left origin) in
the sidecar the moment you commit — the sidecar is the only storage, matching `Session.setCrop`
/ `save` in the core spec.

**Enter:** `c` on the current photo (also a crop toolbar button and `Crop 3:2` row in the Info
pane, which re-enters with the existing rect). It is `c`, not `⌘C` — `⌘C` stays Copy.

**Crop HUD** replaces the toolbar middle: `CROP · aspect · W×H px · <rejected warning>`.

**Overlay:** dimmed (55 % black) outside the rect, bright inside, rule-of-thirds grid lines,
eight square handles (4 corners + 4 edges) drawn in aqua; rect border purple.

**Aspect presets:** `a` cycles **Free → 3:2 → 4:3 → 1:1 → 16:9 → 2:3 → 3:4 → 9:16 → Free**.
One key, one predictable next state; the current ratio is always visible in the HUD, so no
picker UI is needed. With an aspect locked, resizing keeps the ratio anchored at the opposite
corner; switching presets re-centres the largest rect of that ratio inside the current one.

**Mouse:** drag inside = move; drag a handle = resize (edge handles keep aspect when locked);
drag outside the rect = draw a fresh rect. Max ~85 % of the frame for the rect so there is
always outside to grab.

**Keyboard in crop mode:** arrow keys move the rect 1 % of frame per press, Shift+arrow moves
5 %; `a` cycles aspect; `r` resets to full frame (equivalent to removing the crop once
committed); **Enter commits and exits** (sidecar written, stay on the same photo so you can
inspect the result); **Esc cancels** (rect reverts to the stored value, no write). While in
crop mode all cull/nav/zoom keys are dead except `?` and `Esc` — a modal editing state must
not surprise-write decisions.

**Commit writes `crops[STEM]`** (or removes it on full-frame); if the photo is rejected the
write still happens but the HUD shows `rejected — crop never exported`, because finalize
trashes rejects and never consults their crop.

**Indicators:**

- Filmstrip: 2 px purple top border on the thumb + a small `✂` glyph in the badge strip, and
  the thumb renders through `ImagePipeline.crop` at thumbnail size so the strip shows the crop.
- Sessions list: purple `✂ n` chip after the counts (`n = SessionRow.cropped`).
- Info pane: `Crop` row showing the ratio (`3:2`, `Free`, or none).
- The main preview always shows the crop live; hold `H` (Hathaway?) — no: hold **Shift** to
  peek the uncropped frame? Not needed: `r` in crop mode resets, and the Info row states the
  crop. Keep it simple: no peek modifier.

```
│ 2 IMAGE — CROP · 3:2 · 4160×2773 px                                             │
│ ┌────────────────────────────────────────────────────────────────────────────┐  │
│ │ ▓▓▓▓▓▓▓▓▓▓▓▓┌▣─────────▣─────────────▣┐▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │  │
│ │ ▓▓▓▓▓▓▓▓▓▓▓▓│:    :     │      :        │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │  │
│ │ ▓▓▓▓▓▓▓▓▓▓▓▓│:    :     │      :        │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │  │
│ │ ▓▓▓▓▓▓▓▓▓▓▓▓└▣─────────▣─────────────▣┘▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │  │
│ └────────────────────────────────────────────────────────────────────────────┘  │
│      ▣ = aqua handle · ▓ = dimmed · : = thirds · border purple                  │
│      a 3:2 · arrows move (⇧ 5%) · r reset · ⏎ commit · esc cancel               │
```

---

## 3. Preview interaction (zoom & pan)

A photo always opens at **Fit**. Zoom model: Fit = 100 % baseline scale, user zoom is a
multiplier on it; zooming keeps the point under the cursor pinned. Range: Fit … Fit×8.

- `f` **Fit** — whole image visible, centred, letterboxed.
- `F` **Fill** — scale so the frame has no letterbox (overflow clipped); fastest way to
  long-edge-check without hunting zoom steps.
- `0` **1:1** — image pixels at screen points (capped at Fit×8).
- `+` / `=` in, `-` out — 25 % multiplier steps, cursor-anchored.
- Trackpad pinch and ⌘-scroll zoom (continuous, also cursor-anchored) — the native affordances
  photographers already expect.
- **Pan:** plain drag anywhere when zoomed past Fit (open-hand cursor). Arrow keys pan by
  80 pt when zoomed; at Fit they do nothing.
- **Double-click** toggles 1:1 at the click point ↔ Fit.

**Collision rules:** lowercase `f`, `0`, `+`, `-` never collide with the cull set
(`j k z x o J K 1-4 Tab : ?`) or crop keys (`c a r`). `F` is safe because finalize is `:F`
inside command mode, never bare `F`. `1`–`4` stay pane focus in all modes, so zoom keys had to
avoid digits entirely — hence `0` for 1:1. Zoom state resets to Fit on every photo change
(resume is about `last_index`, not viewport state).

---

## 4. Menu bar extra

`MenuBarExtra` with a lens/aperture glyph, **always installed** while the app runs. It exists
so the card-plug → ingest loop works without bringing the window forward.

- **Idle:** plain icon. Hover tooltip: `photocull — 3 sessions in inbox`.
- **Ingesting:** icon becomes a tiny progress ring and the label shows `42 %`.
- Menu items:
  1. `Open PhotoCull` (activates the window; always first).
  2. `Ingest from "SDXC"` — one item per detected card (DCIM under `/Volumes/*`); disabled
     with `No card detected` when none.
  3. During ingest: a disabled progress line `Ingesting 42/118 — DSCF2771.JPG` + `Cancel
     Ingest` (stops after the in-flight copy; nothing is deleted, partial result is kept).
  4. `Open Inbox in Finder`.
  5. `Quit PhotoCull` — disabled while an ingest is running.
- Ingest started from the extra runs in the same `Ingest` pipeline; on completion a user
  notification fires: `Ingested 118 photos (3 skipped) into 2 sessions`.

---

## 5. Keyboard map (final)

Command mode (`:`) accepts exactly `f`, `F`, `i` as in the web app. Contexts: **View** =
normal culling; **Crop** = crop mode; **Modal** = help/finalize/ingest sheet; **Pane 1** =
sessions list focused.

| Key | Context | Action |
|-----|---------|--------|
| `j` | View | Next photo |
| `k` | View | Previous photo |
| `J` | View | Previous undecided photo |
| `K` | View | Next undecided photo |
| `z` | View | Toggle keep |
| `x` | View | Toggle reject |
| `o` | View | Open current JPG in macOS Preview (original, uncropped) |
| `c` | View | Enter crop mode |
| `f` | View | Zoom to Fit |
| `F` | View | Zoom to Fill |
| `0` | View | Zoom to 1:1 |
| `+` / `=` / `-` | View | Zoom in / out (cursor-anchored) |
| arrows | View (zoomed) | Pan 80 pt |
| `1` `2` `3` `4` | all | Focus pane 1/2/3/4 |
| `Tab` | Pane 1 | Cycle session filter All → Active → Done |
| `Space` | Pane 1 | Toggle selection for multi-finalize |
| `Enter` | Pane 1 | Open selected session |
| `Esc` | Pane 1 | Clear all selections |
| `:` | View | Enter command mode |
| `:f` + ⏎ | command | Finalize current session (opens confirm sheet) |
| `:F` + ⏎ | command | Finalize selected sessions (all visible if none selected) |
| `:i` + ⏎ | command | Open ingest sheet |
| `?` | any | Help overlay |
| `y` / `n` | Modal | Confirm / cancel sheet (finalize) |
| `a` | Crop | Cycle aspect preset |
| arrows | Crop | Move rect 1 % (Shift = 5 %) |
| `r` | Crop | Reset rect to full frame |
| ⏎ | Crop | Commit crop to sidecar, exit crop mode |
| `Esc` | Crop / Modal | Cancel (revert crop / close sheet) |

`Esc` in View closes overlays and clears selections, as in the web app. There is no
auto-advance after `z`/`x` — the web app doesn't, and `J`/`K` already cover
"next undecided" deliberately.

**Help overlay (`?`):** the table above, split into the same two columns as the web app
(Actions | Navigation), plus a third column for View/Crop keys. One overlay, one truth: the
help is generated from the same key map, so the table and the help can never drift.

---

## 6. Visual design

**Palette — Everforest Dark (medium), same token names as `style.css`:**

| Token | Hex | Use |
|-------|-----|-----|
| `bg0` | `#2b3339` | window & image backdrop |
| `bg1` | `#343f44` | toolbar, pane headers, status bar |
| `bg2` | `#3d484d` | sheets, hover fill, focused pane header |
| `bg3` | `#475258` | selection fill, borders, `kbd` chips, pane badges |
| `fg` | `#d3c6aa` | primary text |
| `subtle` | `#859289` | muted text, separators, empty states |
| `red` | `#e67e80` | reject, destructive buttons |
| `orange` | `#e69875` | in-progress status, warnings |
| `yellow` | `#dbbc7f` | finalize action accents |
| `green` | `#a7c080` | keep, complete status |
| `aqua` | `#83c092` | focus ring, wordmark, crop handles, filter chip |
| `blue` | `#7fbbb3` | links (Open in Finder…) |
| `purple` | `#d699b6` | session selection, crop markers |
| `border-focus` | aqua | focused pane border |
| `border-selection` | purple | selected session row |

Decisions: dark **only** in v1, ignoring system appearance — photos judge better on dark and
the Everforest identity is the app's brand. Exactly 2 px borders, 3 pt corner radius, and a
single shadow (sheets only: 0/8/24 black 40 %) — flat terminal look everywhere else.

**Typography:** SF Mono everywhere (the web app is mono-only and that *is* the identity).
Sizes: 15 semibold wordmark · 14 bold dates/filename · 13 body, info values, pane titles
(semibold, uppercase, 6 % tracking) · 12 meta rows, status-bar hints · 11 badges. Ligatures
off; tabular numbers in counters.

**Spacing:** 4 pt base grid. Toolbar 48 · status bar 28 · pane-header 36 · pane padding 12 ·
session rows 8×6 · thumb 74 with 6 gap · sidebar 320 · filmstrip 120.

**Badges** (uppercase, bold, 2 px border, 15 % tint fill, 3×8 padding):

- `KEEP` green · `REJECT` red · `UNDECIDED` subtle border, no fill.
- Session status: `UNSTARTED` subtle outline · `IN PROGRESS` orange · `COMPLETE` green.
- `✂ n` purple — cropped count (row) / crop marker (thumb top bar + glyph).
- Rejects in filmstrip keep the web treatment: `brightness 0.35, saturate 0.3` + red bottom
  bar; current thumb gets the aqua ring regardless of decision.

**Info pane:** two-column grid, labels subtle left, values `fg` right, rows only when the
value exists — plus the new `Crop` row and `Capture` row (`yyyy-MM-dd HH:mm:ss`, from
`PhotoInfo.dateTimeOriginal`; capture time is culling-relevant for burst gaps).

---

## 7. Ingest flow

Ingest is a **sheet** over the main window, opened by `:i`, the toolbar button, or the menu
bar extra (which activates the window first). One flow, three entry points, one implementation.

1. **Detection:** on sheet appear, scan `/Volumes/*` for `DCIM` subdirs (core spec §6), show
   one radio row per card: volume name + path (`SDXC — /Volumes/SDXC/DCIM`). A `Rescan`
   button re-runs detection without closing the sheet.
2. **Manual path:** text field pre-filled with the first card (empty when none) + `Browse…`
   (open panel) — covers card offloads already copied to disk, as the web app does.
3. **Start:** validates the path, disables the form, shows a determinate bar driven by
   `IngestProgress` (`total` once, then `current/copied`): bar, `Copied 42/118`,
   current filename, `Skipped 3`. `Cancel` stops after the in-flight copy and reports partial
   counts; no cleanup, files already copied stay.
4. **Completion summary** replaces the form: `Ingest complete — copied 118, skipped 3
   duplicates, 2 sessions (2026-05-14, 2026-05-15)`. Buttons: **Start culling** (opens the
   first folder written — ingest date order — and closes the sheet) and **Close**.
5. **Errors** (`noSourceFound`, `scanFailed`, copy I/O): inline error line above the buttons,
   counts-so-far kept visible; the sheet never auto-closes on error.

Multi-date ingests are the norm (cards spanning midnight), so the summary always lists every
folder written, and "Start culling" opens the **newest** of them.

**Finalize sheets** (single `:f`, multi `:F`) mirror the web modals: per-session count table
(keep/reject/undecided + RAW counts), the orange `Undecided files will be treated as KEEP`
warning, destinations line, plus one new control: an **Apply crops to dump** toggle, default
**on** and persisted in app storage — it maps to `CropExportMode.applyCrop` vs `.original`
and is the only new decision finalize needs. Confirm `y` / cancel `n`; the result toast shows
`archived / trashed / dumped / cropped` counts from `FinalizeResult`.
