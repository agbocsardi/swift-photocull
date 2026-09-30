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
- [x] 323 automated checks passing
- [ ] Apply `--repair-pairs` to the real library (**needs user approval**)
- [ ] Confirm the crop UX feels right in a real culling session
- [ ] Optional: RAW (RAF/RW2) preview decoding via Core Image
- [ ] Optional: light-mode palette
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
