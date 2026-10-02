# PhotoCull performance audit — 2026-10-02

Consolidated from four parallel read-only reviews (zai/glm-5.3-flash sub-agents):
`/tmp/perf-audit/{hotpath,pipeline,render,misc}.md`. Reports' line numbers verified against each other.

## Executive summary

The app's decode path, build config, and crop-overlay drawing are already optimal. The lag comes
from **repeating expensive work on every interaction frame and every keystroke**:

1. **`displayImage` is a computed property** (ImagePane.swift:15–29) evaluated 1–2× per body — it
   synchronously re-runs the full CPU edit pipeline (quarter-turn → tilt resample of a 45–67 MB
   bitmap → crop) on the main thread whenever *any* of the app's ~30 `@Published` properties
   changes — pan, zoom, hover, toasts, anything. Each run allocates a fresh CGImage → ~45 MB
   texture re-upload per frame.
2. **`AppState` is a god-object** observed by ~160 view bodies (148 filmstrip cells + 4 panes +
   chrome). Every drag tick / key-repeat / decode arrival invalidates all of them.
3. **Every culling keystroke does synchronous disk IO on the main thread**: a full inbox rescan
   per decision (`refreshRows`), 2 EXIF reads + 1–2 sidecar writes per navigation, and finalize
   runs entirely on the main thread.

## Consolidated findings

### Tier 0 — the reported crop/tilt lag

| # | Finding | Where | Impact | Effort |
|---|---------|-------|--------|--------|
| 0.1 | `displayImage` recomputes full pipeline per body eval (2× per body), even with unchanged inputs; new CGImage identity per frame → texture churn | ImagePane.swift:15–29, 41, 105; ImagePipeline.swift:117–196 | high | S/M |
| 0.2 | Live tilt preview goes through CPU `rotateToFill` per 0.25° tick (~360 full resamples per slider sweep) — the one case memoization can't fix (input itself changes) | ImagePane.swift:19–24; AppState.swift:482 | high | M |
| 0.3 | `pan`/`zoom`/`cropRect`/`cropTilt` on app-wide AppState → ~160 bodies re-evaluated per drag frame | AppState.swift:128–139; ImagePane.swift:85,141; CropOverlay.swift:95–114 | high | M |
| 0.4 | `.shadow(radius: 12)` on the full-size photo = full-canvas Gaussian per interaction frame | ImagePane.swift:55 | med | S |

### Tier 1 — per-keystroke main-thread stalls

| # | Finding | Where | Impact | Effort |
|---|---------|-------|--------|--------|
| 1.1 | Every z/x decision → full inbox rescan (`Library.loadSessions`: N dir reads + N sidecar parses, MainActor) | AppState.swift:412 (`refreshRows`) | high | S |
| 1.2 | Double `ExifReader.read` per navigation (`currentMaxPixel` re-reads what `loadCurrent` just read) | AppState.swift:282, 294–298 | high | S |
| 1.3 | `persist()` sidecar write per navigation keystroke; one `z` = 2 writes + rescan + 2 EXIF reads | AppState.swift:301, 361–369, 331 | med | S |
| 1.4 | `imageLoader.objectWillChange` manually forwarded into `app.objectWillChange` → every decode arrival invalidates ~160 bodies (2–3× per j/k) | AppState.swift:175–176 | med | S |
| 1.5 | Every `ThumbCell` observes the god-object (for one tap closure) → 148 cells in every storm | FilmstripPane.swift:59, 165 | high | S |
| 1.6 | `ThumbnailStore.generation` bumps per arrival × 148 subscribed cells ≈ **22k body evals** burst on session open | ImageLoader.swift:90; FilmstripPane.swift:65 | high | S |
| 1.7 | Rapid j/k piles up uncancellable 24–48 MP decodes (stale ones run to completion) | ImageLoader.swift:26–34 | med | S/M |

### Tier 2 — bulk operations & startup

| # | Finding | Where | Impact | Effort |
|---|---------|-------|--------|--------|
| 2.1 | `Finalize.run`/`runMulti` fully on MainActor — UI frozen for whole operation, no progress | AppState.swift:617 | high | S |
| 2.2 | Startup before first frame: config load+write, SD detect (network-mount hazard), full library scan, then `open()` re-scans the same folder + 2 EXIF reads | AppState.swift:168–183 | med | S/M |
| 2.3 | Ingest progress callback per copied file → ~2,000 whole-window invalidations per card | AppState.swift:655–661; Ingest.swift:124 | med | S |
| 2.4 | `Finalize.summary` scans folders synchronously on sheet open / right-click | AppState.swift:600–615; Finalize.swift:32–56 | med | S |
| 2.5 | Session-switch chain serial on MainActor + duplicates the scan `loadSessions` just did | AppState.swift:256–273 | med | M |
| 2.6 | `PairRepair.plan` (inbox+archive walk) on main thread from menu | AppState.swift:700–712 | low | S |

### Tier 3 — memory & polish

| # | Finding | Where | Impact | Effort |
|---|---------|-------|--------|--------|
| 3.1 | Image caches are entry-counted: 16 × ≤4096px decoded RGBA ≈ **0.7–1.1 GB** steady state | ImagePipeline.swift:200–236; ImageLoader.swift:10 | med | S |
| 3.2 | `AnyView` in all four `SectionHeader`s blocks structural diffing | Theme.swift:372 + 4 panes | low | S |
| 3.3 | Redundant `.id(row.date)`; per-cell shadow×148; toast scoped app-wide | SessionsPane.swift:31; FilmstripPane.swift:137–141; AppState.swift:768 | low | S |
| 3.4 | `createDirectory` per copied file | Ingest.swift:106 | low | S |

## Verified already fine — no work needed

- **Decode path**: one-pass `CGImageSourceCreateThumbnailAtIndex` with transform-on-decode,
  cache-immediately, O(1) `cropping(to:)`. Optimal.
- **Build config**: dist is `-c release` (`-O` + WMO). No flag changes needed.
- **CropOverlay drawing**: even-odd path + thirds + 8 handles = negligible. Don't micro-optimize.
- **KeyMonitor**: local monitor, cheap early-outs. Per-key cost is what handlers *do* (Tier 1).
- **InfoPane**: renders cached `app.info`; no per-render EXIF reads.
- **HStack filmstrip**: deliberate (documented LazyHStack regression). Keep.

## Anti-recommendations (measured dead ends)

- `.equatable()`/`EquatableView` on cells holding `@EnvironmentObject` is a **no-op** — object
  invalidation bypasses equality. Decouple subscriptions first.
- No `.drawingGroup()` on panes — materials/shadows don't survive group rendering.
- **vImage/Metal are not the lever** — the cost is *repetition*, not resampler throughput.
- Don't revisit `LazyHStack`.

## Fix plan

- **Wave 1 (quick wins, all low-risk):** 0.1 memoize `displayImage` · 0.4 gate shadow in crop
  mode · 1.1 in-place row update (no rescan) · 1.2 kill double EXIF read · 1.3 debounce persist ·
  1.4 drop loader forwarding · 1.5 ThumbCell closure · 1.6 coalesce generation bumps · 1.7 stale
  decode early-out · 2.1 finalize off-main + progress + re-entry guard · 2.3 ingest progress
  throttle · 3.1 byte-budget caches · 3.2–3.4 polish.
- **Wave 2 (structural):** 0.2 GPU live tilt (`.rotationEffect` + shared `coverScale()` helper;
  exact CPU pipeline at commit) · 0.3 extract `CanvasState`/`CropState` sub-objects · 2.2 startup
  diet (drop init SD detect, reuse scanned data, defer) · 2.4 async summaries · 2.5 async session
  open · 2.6 detached pair-repair.

**Deliberately skipped:** single-context combined export transform (transform-algebra risk for an
export-time-only win), `noneSkipLast` alpha info (percent-level), Metal/vImage (not the lever).
