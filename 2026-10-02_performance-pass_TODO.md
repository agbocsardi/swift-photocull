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
  - [ ] perf-view agent: GPU tilt + memoization + view scoping (branch `perf-view`)
  - [ ] perf-state agent: main-thread IO + threading (branch `perf-state`)
  - [ ] Integrate both branches onto `performance`, resolve fallout

- [ ] Re-verify: 348 checks pass, snapshot renders, live crop/tilt feels snappy
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
