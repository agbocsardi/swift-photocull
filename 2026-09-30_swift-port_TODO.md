# PhotoCull Swift port — TODO

## Tasks

- [x] SwiftPM package scaffold (`PhotoCullCore` + `PhotoCullApp` + `PhotoCullTests`)
- [x] Custom test harness (XCTest unavailable without Xcode)
- [x] `Config` — TOML config, byte-compatible with the Go app
- [x] `Session` — `.photocull.json` sidecar, byte-compatible + additive `crops` key
- [x] `FilePairs` — JPG/RAW pairing by stem
- [x] `Library` — session rollups, newest-first
- [x] `ExifReader` — ImageIO metadata, capture date, orientation
- [x] `Ingest` — SD card detect, EXIF date folders, collision-safe copy, progress
- [x] `Finalize` — Trash rejects, archive keepers, dump JPGs, single + multi-session
- [x] `ImagePipeline` — decode/downsample/orient/crop/encode + LRU cache
- [x] `PairRepair` — heal RAWs renamed `_2` by the old stem-keyed rule
- [x] SwiftUI app: 4-pane cull window, header, footer, command bar, toasts
- [x] Sessions pane with filter, multi-select, progress bars
- [x] Image pane with zoom / pan / fit
- [x] **Non-destructive crop** — overlay, handles, aspect presets, sidecar storage
- [x] Info pane (EXIF + crop + path)
- [x] Filmstrip with decision and crop badges
- [x] Menu bar extra: sessions, ingest with progress, finalize, repair
- [x] Keyboard dispatch (`KeyMonitor`) matching the cull keymap
- [x] `scripts/build-app.sh` → `dist/PhotoCull.app`
- [x] `PhotoCull --check` headless diagnostic
- [x] 326 automated checks passing
- [x] Apply `--repair-pairs` to the real library (user approved; 1116 RAW renames audited)
- [x] Native light/dark UI, portrait-fit filmstrip, and scythe app icon
- [x] Arrow-key navigation alongside j/k
- [ ] Confirm the crop UX feels right in a real culling session
- [ ] Optional: RAW (RAF/RW2) preview decoding via Core Image
- [x] Semantic light/dark palette
- [ ] Optional: video file support

## Open questions for the user

1. Crop semantics — non-destructive sidecar (implemented) vs overwrite the JPG?
2. Should `--repair-pairs --apply` be run on the real inbox + archive?
3. Menu bar scope — is the current set of actions right?
4. Keep the Go webapp, or retire it once the Swift app is trusted?

## Log

### 2026-09-30

Built the whole Swift port in one session, using four parallel `glm-5.3-flash` subagents in
separate git worktrees for the core library and the design pass, with the SwiftUI app written
in the main worktree.

Key decisions:

- **Toolchain.** No Xcode on this machine, so no `.xcodeproj` and no `swift test`. The app is a
  SwiftPM package assembled into a `.app` by `scripts/build-app.sh`; tests run through a custom
  harness executable. The `@State` macro cannot expand without the `SwiftUIMacros` plugin, so
  local view state uses `@StateObject` + a small `ViewState` wrapper instead.
- **Crop is non-destructive.** Stored as a normalised rect in `.photocull.json`; originals are
  never modified. Applied only when writing a keep-JPG to the dump folder on finalize.
- **Fixed a real bug from the Go app.** `safeDestName` counted collisions per uppercased stem,
  so ingesting `DSCF0001.JPG` + `DSCF0001.RAF` in one run renamed the RAW to `DSCF0001_2.RAF`
  and destroyed the pair. The Swift port keys on the full filename. The user's library already
  carries this damage (1042 JPGs vs 972 RAWs, almost all renamed `_2`), so `PairRepair` and
  `PhotoCull --repair-pairs` were added. Dry run reports 1116 repairable RAWs.
- **`j`/`k`.** Go's `keys.js` had them reversed relative to its own README; the port uses the
  vim convention (`j` = next).

Verified: 323/323 checks pass; `PhotoCull --check` reads a real 28-session inbox, decodes a
6240×4160 RAF-paired JPG at 2048px in ~123 ms, applies a 50% crop, and builds a thumbnail.
The library was inspected read-only — no file in `~/Pictures/PhotoCull` was modified.

Next: get approval before running `--repair-pairs --apply`, and try a real culling session.

### 2026-09-30 (follow-up) — filmstrip, arrow navigation, scythe icon

The filmstrip now fits full EXIF-oriented photos without cropping; portrait frames display
upright within 80×88pt slots, and the selection ring hugs the actual image dimensions. Raised
the strip to 160pt. Verified light and dark app-bundle snapshots; the initial live mismatch came
from an older running app, which was quit and reopened with the current bundle.

Arrow keys now supplement vim keys: left/right navigate photos in every pane; up/down navigate
sessions while the sidebar has focus and photos elsewhere. Crop mode intercepts arrows first.
The help sheet, status hint, and README now describe the mapping.

The first icon revision looked like a second ring arc at 32px. The final revision draws an amber
scythe as one silhouette with a substantial diagonal handle and hooked blade over a six-blade
aperture; checked raster renders at 16/32/64px before packaging.

Verified: `swift build` and `swift run PhotoCullTests` (326 checks).

### 2026-09-30 (hover tips and menu bar icon)

Added descriptive native hover tips to the photo action bar, sidebar controls, inspector,
ingest/finalize sheets, and menu-bar actions. Corrected the preview toggle tip: `p` only
works in crop mode. The sidebar filter label is now a real clickable button. The menu bar
uses the bundled app icon, with a development fallback outside an app bundle. The first
complex label (Group + overlay) made the status item vanish; a single 18pt image fixed it.
Verified by a direct screen capture of the running app after relaunch.

### 2026-09-30 (menu bar outline)

User feedback: the full-color square app icon appeared after simplifying MenuBarExtra to a
single image, but was too heavy among macOS menu-bar glyphs. Replaced it with a transparent
monochrome outline of the same aperture-and-scythe motif as a template image. The colorful
Dock icon remains unchanged; the menu-bar glyph follows system light/dark tint.

Validation: checked 18/36/54px raster previews on dark and light sample backgrounds;
`PhotoCullMenuBar.png` is 36×36 transparent. The running app reports one enabled, clickable
36×24pt status item through Accessibility. The display returned black screen captures (likely
locked/asleep), so the new glyph was not visually verified in the live system menu bar.
`swift build`, the release bundle build, and all 326 core checks passed.

### 2026-09-30 (appearance preference)

Added a toolbar Appearance menu with System / Light / Dark. System (default) inherits macOS
automatically; Light and Dark override PhotoCull only. Preference persists in UserDefaults,
not the shared Go config. Menu-bar outline still uses system tint.

Verified from the packaged release app: a saved Dark preference rendered dark without any
snapshot override; after deleting that temporary preference, System rendered light to match
the current macOS setting. Restored the original unset preference before relaunch.
`swift run PhotoCullTests` passed all 326 checks.

### 2026-10-02 — mouse parity for session selection

- **Bug:** sidebar clicks didn't open sessions — single click only moved the invisible
  keyboard cursor, and the double-tap gesture was attached *after* the single-tap, so the
  single-tap recognizer won the race and double-click never reliably fired.
- Fix: single click opens the session (= `Enter`); ⌘-click toggles multi-finalize selection
  (= `Space`, native macOS idiom); broken double-tap removed.
- Pane focus on click (= `1`–`4` keys) via simultaneous tap gestures on all four panes,
  so ↑/↓ after a click act in the clicked pane.
- Help sheet gained a Mouse column; README gained a Mouse section. 326 checks pass;
  snapshot renders. Not yet verified by hand in a live session.

### 2026-10-02 (follow-up) — filmstrip thumbnail refresh

- ThumbCell slots pin identity to the slot index (`.id(i)`), so `.onAppear` fired only
  once per slot; after switching sessions the new photos never started loading and the
  filmstrip kept spinning. Latent since the filmstrip landed; surfaced by mouse session
  hopping. Fixed with `.task(id: pair.jpg)`. Committed bb56995.

### 2026-10-02 (follow-up 2) — filmstrip identity fix, verified live

- `.task(id: pair.jpg)` alone wasn't enough: cells were still identified by slot index
  (`.id(i)` overrode the ForEach id), so lazy-stack reuse kept stale pictures. Cell identity
  is now the photo's full URL (`id: \.element.jpg`, `.id(i)` removed; scrollTo follows).
  Session switch now rebuilds every cell. User confirmed working in the live app.
