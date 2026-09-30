# PhotoCull (Swift)

A native macOS app for the full RAW+JPG photo culling workflow: ingest from an SD card,
cull with the keyboard, crop non-destructively, and finalize — archiving keepers, trashing
rejects with their paired RAWs, and dropping keep-JPGs into a folder ready for Apple Photos.

This is a Swift/SwiftUI port of the Go web app in `../photocull`. It shares the same config
file, the same directory layout, and the same `.photocull.json` sidecar format, so both apps
can work on the same library.

## Status

Working end to end. Verified by 326 automated checks plus a headless run against a real
28-session inbox (`swift run PhotoCull --check`).

| Area | State |
|------|-------|
| Ingest (SD card, EXIF dates, collision-safe copy) | done |
| Sessions sidebar, filters, multi-select | done |
| Cull (keep/reject/undecided, vim keys, filmstrip) | done |
| EXIF inspector | done |
| Preview (zoom, pan, fit, 1:1) | done |
| **Non-destructive crop** (new in the Swift port) | done |
| Finalize (single + multi-session, Trash, archive, dump) | done |
| Menu bar extra with ingest progress | done |
| RAW pair repair tool | done |
| App icon (SVG to .icns) | done |
| Native macOS design pass | done |

## Build

Requires macOS 14+ and the Swift toolchain. No Xcode project — this is a SwiftPM package,
and the app bundle is assembled by a script.

```bash
swift build                 # build the package
swift run PhotoCullTests    # run the core test suite (exit 0 = pass)
./scripts/build-icon.sh     # optional: rebuild resources/PhotoCull.icns from icon/icon-a.svg
./scripts/build-app.sh      # build dist/PhotoCull.app
open dist/PhotoCull.app
```

XCTest is not available in a CommandLineTools-only toolchain, so tests run through a small
custom harness (`Sources/PhotoCullTests/Harness.swift`) rather than `swift test`.

### Known toolchain constraint

The `@State` SwiftUI macro needs the `SwiftUIMacros` plugin, which ships only with Xcode.
On a CommandLineTools-only machine, `@State` fails to expand. This project therefore uses
`@StateObject` plus the tiny `ViewState` wrapper in `Theme.swift` instead. Do not introduce
`@State`, `@Entry`, or `@Animatable`.

## Usage

```bash
PhotoCull                 # launch the app
PhotoCull --check         # headless diagnostic against the real inbox
PhotoCull --repair-pairs  # dry run: report RAW files broken by the old naming bug
PhotoCull --repair-pairs --apply
```

## Layout

```
+---------------------------------------------------------------+
| traffic lights   [3/81] DSCF0679.JPG  UNDECIDED  +RAF   ingest |
+--------------+--------------------------------+---------------+
| (1) SESSIONS | (2) CANVAS            100%      | (3) INFO      |
| 2026-08-18   |                                | PHOTO         |
| 2026-08-16   |        [ the photo ]           | CAMERA        |
| 2026-08-15   |                                | CULL          |
|              |   ( keep reject crop zoom )    | LOCATION      |
|              +--------------------------------+               |
|              | (4) FILMSTRIP        3 of 81   |               |
+--------------+--------------------------------+---------------+
| z keep  x reject  c crop  j/k next/prev  :f finalize ...      |
+---------------------------------------------------------------+
```

## Design

The app follows Apple's Human Interface Guidelines rather than the Go web app's terminal
aesthetic. `Sources/PhotoCullApp/Theme.swift` is the whole design system:

| Concern | Approach |
|---------|----------|
| Layout | `NavigationSplitView` — sidebar (sessions) + content (canvas, filmstrip) + `.inspector` (info) |
| Chrome | Real unified toolbar; traffic lights and the drag zone behave natively |
| Type | SF Pro on Apple's scale (13pt body). SF Mono only for filenames, paths and keycaps. Nothing below 9pt |
| Colour | Semantic system colours, so light and dark both work and the user's accent colour is respected |
| Depth | Materials/vibrancy for sidebar, inspector, filmstrip and status bar; layered shadows on floating chrome |
| Spacing | One `Metric.paneInset` (16pt) shared by all four panes, on an 8pt grid |

**Panes are numbered 1-4** (Sessions, Canvas, Info, Filmstrip) and addressable with those keys.
Each header shows its numeral, and the numeral lights up in the accent colour while that pane
has keyboard focus. Panes must not contain raw spacing numbers — everything routes through
`Metric` / `Typo` / `Palette`.

The icon (`icon/icon-a.svg`) pairs a six-blade camera iris with a distinct amber
scythe: camera first, scythe second. The menu bar uses the same bundled icon. Build it with
`scripts/build-icon.sh`, which rasterizes the SVG through AppKit (no third-party renderer)
and produces `resources/PhotoCull.icns`.

### Verifying the UI without Screen Recording permission

```bash
swift build
.build/debug/PhotoCull --snapshot /tmp/ui.png --appearance dark   # renders its own window to PNG
.build/debug/PhotoCull --snapshot /tmp/crop.png --crop            # with crop mode open
```

An app may snapshot its own window without Screen Recording permission, so this is the way to
inspect the interface from a terminal or an agent context.

## Keyboard

| Key | Action |
|-----|--------|
| `z` / `x` | mark keep / reject (press again to undo) |
| `j` / `k` | next / previous photo |
| `→` / `←` | next / previous photo (in any pane) |
| `↓` / `↑` | next / previous photo, or session when pane 1 has focus |
| `J` / `K` | next / previous **undecided** photo |
| `c` | enter crop mode |
| `o` | open the current JPG in Preview |
| `f` | reveal in Finder |
| `+` / `-` / `0` | zoom in / out / fit |
| `1`-`4` | focus sidebar, canvas, info, filmstrip |
| `Tab` | cycle the session filter (pane 1) |
| `Space` | select a session for multi-finalize (pane 1) |
| `Enter` | open the selected session / apply the crop |
| `:f` `:F` `:i` `:c` `:R` `:q` | finalize / finalize all / ingest / crop / repair pairs / quit |
| `?` | help |

**Crop mode:** arrows move the region, `Shift`+arrows resize, drag the handles with the mouse,
`a` cycles the aspect ratio, `r` resets to full frame, `p` toggles the cropped preview,
`Enter` applies, `Esc` cancels.

## Crop is non-destructive

A crop is stored as a normalised rectangle in `.photocull.json` next to the cull decisions.
**The original JPG and RAW are never modified.** The crop is applied only when the finalize
step writes a keep-JPG into the dump folder; you can choose "originals" instead in the
finalize sheet. `Esc` or "Clear" in the inspector removes a crop.

## Data compatibility

| Thing | Location |
|-------|----------|
| Config | `~/.config/photocull/config.toml` (TOML, same keys as the Go app) |
| Inbox | `~/Pictures/PhotoCull/inbox/<YYYY-MM-DD>/` |
| Archive | `~/Pictures/PhotoCull/archive/<YYYY-MM-DD>/` |
| Dump | `~/Downloads/<date>/` (or `<first> to <last>` for multi-session) |
| Session state | `<date>/.photocull.json` — `version`, `decisions`, `last_index`, plus `crops` |
| Repair logs | `~/.config/photocull/pair-repair-<timestamp>.json` |

`crops` is additive: the Go app ignores it, and this app ignores nothing the Go app writes.

## Deliberate divergences from the Go app

1. **Ingest collision naming.** Go counted collisions per uppercased *stem*, so ingesting
   `DSCF0001.JPG` and `DSCF0001.RAF` in one run renamed the RAW to `DSCF0001_2.RAF` and
   destroyed the pair. This port counts collisions per full filename, which still handles the
   case Go's tests describe (the same filename from two camera folders) but keeps pairs intact.
   `--repair-pairs` fixes libraries already damaged by the old rule.
2. **`j`/`k` direction.** The Go app's `keys.js` maps `j` to *previous* while its own README
   and footer say next/previous. This port uses the vim convention: `j` = next, `k` = previous.

## Not implemented

- RAW decoding for display. RAW files are paired, moved and trashed, but only JPGs render.
  (Core Image could decode RAF/RW2 if wanted — `ImagePipeline` already goes through ImageIO.)
- Video files.
- Duplicate detection across sessions.

## Development notes

- `Sources/PhotoCullCore/` — no UI. Config, session sidecar, file pairing, EXIF, ingest,
  finalize, image pipeline, pair repair. Fully unit-tested.
- `Sources/PhotoCullApp/` — SwiftUI. `AppState` owns the whole cull model and dispatches keys;
  views are thin. `KeyMonitor` installs one `NSEvent` local monitor.
- `docs/CORE-SPEC.md` — the behaviour spec the core was implemented against.
- `docs/DESIGN.md` — the UX/visual design pass.
