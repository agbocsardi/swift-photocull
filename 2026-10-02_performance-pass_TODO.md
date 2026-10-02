# Performance pass TODO

Goal: make PhotoCull snappy end to end. Reported pain: crop + tilt interactions lag.
Branch: `performance`. Audit report: `docs/performance-audit.md`.

## Tasks

- [ ] Create `performance` branch
- [ ] Parallel sub-agent audit (4 reviewers, zai/glm-5.3-flash)
  - [x] hotpath: crop/tilt/zoom/pan per-frame costs (ImagePane, CropOverlay, AppState, ImageLoader)
  - [x] pipeline: decode/rotate/crop/encode + caches (ImagePipeline, Exif, build flags)
  - [ ] render: SwiftUI re-render topology (AppState @Published granularity, filmstrip, overlays)
  - [x] render: SwiftUI re-render topology (AppState @Published granularity, filmstrip, overlays)
  - [x] misc: main-thread IO, ingest/finalize responsiveness, KeyMonitor, startup
- [x] Integrate findings into ranked audit doc → `docs/performance-audit.md`
- [ ] Implement top fixes (ranked by impact/effort)
  - [x] perf-view agent: GPU tilt + memoization + view scoping (branch `perf-view`, 8d338f1, merged)
  - [x] perf-state agent: main-thread IO + threading (branch `perf-state`, 8813f37, merged, 350/350)
  - [x] Integrate both branches onto `performance`, resolve fallout (clean — disjoint files)

- [x] Re-verify: 358 checks pass, `--check` green on real library, snapshot renders (2.5MB, non-blank), release bundle built
- [ ] Live crop/tilt feel test by user
- [ ] Close worktree workspaces wD (perf-view) / wE (perf-state) after user confirms
- [ ] Update README/notes if user-facing behavior changed

## Log

### 2026-10-02 (cont.) — implementation wave dispatched

- Cleaned up the four read-only review tabs after integrating their reports (audit commit 400f4cf).
- Breakthrough plan split into two disjoint file domains, dispatched as two glm-5.3-flash
  worktree agents (branches `perf-view` from 400f4cf, `perf-state` from 400f4cf):
  - **perf-view** (wD): memoized displayImage, GPU live tilt (rotationEffect + shared
    ImagePipeline.coverScale), shadow gating in crop mode, ThumbCell decoupling, generation-bump
    coalescing, byte-budgeted ImageCache, stale-decode early-out, view polish, coverScale checks.
  - **perf-state** (wE): in-place refreshRows (no inbox rescan per decision), no duplicate EXIF
    read, debounced navigation persist, finalize off-main + re-entry guard, async summaries,
    startup diet (no init SD detect), async pair-repair, ingest progress throttle, cached dest
    folder in Ingest.
- Deliberately skipped (recorded in audit): CanvasState/CropDraft extraction (blast radius
  collapses once cells are decoupled + bodies cheap), loader objectWillChange forwarding removal
  (cross-file surgery, low residual cost), combined export transform, noneSkipLast, Metal/vImage.
- Parent integrates both branches onto `performance` when they report, then builds, runs the
  348-check suite, and hands off for live crop/tilt verification.

### 2026-10-02

- Branched `performance` off `main` (was 8 commits ahead of origin, tree clean).
- Parent quick-scan already flagged: `ImagePane.displayImage` computed property re-runs the
  full CPU edit pipeline on every body evaluation (every drag/pan/zoom frame, main thread),
  plus `.shadow(radius: 12)` blurred per frame over the full-size photo.
- Launched 4 read-only review sub-agents in parallel (zai/glm-5.3-flash).

### 2026-10-02 (cont. 2) — both waves merged, verified

- perf-state (8813f37): reviewed diff, merged (18c7855). refreshRows derivation mirrors
  Library.loadSessions field-for-field; flush points at close/finalize/ingest; finalize
  detached + guarded; checkPairing now Void (call sites ignore result). 350/350.
- perf-view (8d338f1): reviewed diff, merged (f062f35). EditKey memo complete (image identity,
  turns, cpuTilt=0-in-crop-mode by design, crop, cropMode, preview flag); GPU chain
  frame→scaleEffect(coverScale)→rotationEffect→clipped→offset keeps CropOverlay geometry
  contract; coverScale extraction is formula-identical to the old rotateToFill math; byte-budget
  eviction never drops the just-stored entry. +8 checks.
- Combined verification on `performance`: swift build clean, 358/358 checks, `--check` green
  against the real library (decode 2048px in ~124ms, cache LRU intact), snapshot renders
  (3024×1896, 2.5MB), release bundle rebuilt (dist/PhotoCull.app, 20:49).
- Known accepted trade-offs: undo of an edit on a non-open session no longer live-updates that
  sidebar row's `total` (sidecar still written; full rescans remain on ⌘R/ingest/finalize);
  debounced persist can lose ≤500ms of remembered position on a hard kill.
- Awaiting user live test; worktree workspaces wD/wE kept until confirmation.
