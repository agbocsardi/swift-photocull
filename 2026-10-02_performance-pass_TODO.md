# Performance pass TODO

Goal: make PhotoCull snappy end to end. Reported pain: crop + tilt interactions lag.
Branch: `performance`. Audit report: `docs/performance-audit.md`.

## Tasks

- [x] Round 2: integrate three reviewer reports (interaction / io / remaining) into audit
- [ ] Round 2: dispatch implementation wave from consolidated findings
- [ ] Round 2: verify (build + full test suite + `--check` + snapshot) and hand off for live feel test
- [ ] Live crop/tilt feel test by user (fresh `dist/PhotoCull.app` built)
- [ ] If pan still janks on huge photos: `CanvasState`/`CropDraft` extraction (deferred — see audit)


## Log

### 2026-10-02 (cont. 7) — perf2-io integrated; all three in; wave 3 dispatched

- Report verified: copyItem sites + detached-QoS claims grep-confirmed; suite re-run by parent →
  **358/358** (reviewer's "356" was a miscount). FAT32 fixture already detached by reviewer.
- Clonefile hunch killed by measurement (copyItem already APFS-clones). Accepted: **B1** parallel
  cropped exports (3.1–3.7× measured), **B2** ingest 2–4-wide workers (SSD 3.7–5.8×, UHS-I
  1.1–1.4× realistic), **B3** beginActivity one-liner, **B4** fileSizeKey nit.
- Round-2 section appended to docs/performance-audit.md (measured facts, accepted A1–A7/B1–B4,
  rejected list). Committed before dispatch so implementers branch from it.
- Implementation wave 3 = two worktree agents (zai/glm-5.3) on disjoint file domains:
  - **perf2-app** (branch `perf2-app`): A1–A7 — Sources/PhotoCullApp/** only.
  - **perf2-io-impl** (branch `perf2-io`): B1–B4 — Sources/PhotoCullCore/{Ingest,Finalize}.swift
    + PhotoCullTests. No file overlap; parent merges both.

### 2026-10-02 (cont. 6) — perf2-interaction integrated (probe re-verified by parent)

- Re-ran `/tmp/perf2/probe` against real PhotoCullCore sources: cliff confirmed —
  load(3072)=91 ms vs load(4096)=197 ms median; embedded-thumb 0.4 ms vs 87 ms; 2-wide
  prefetch 1.73×; open() chain ≈5 ms. mark→setIndex→prefetch chain grep-verified (AppState:416+).
- Ran `/tmp/perf2/thumbcheck` on real inbox (parent-only): 4 sessions, 49 files —
  **all EMBEDDED** → filmstrip burst already on the fast path (~45 ms/session). **F4 closed,
  no work.**
- Findings accepted: **F1** instant 256px-thumb placeholder in ImagePane loading branch (+
  crossfade, quarter-rotation only, spinner fallback); **F2** decode cap 4096→3072 (one token;
  −53% miss decode, cache 45→25 MB/slot ≈ 20 photos warm); **F3** prefetch 2-wide TaskGroup +
  inFlight dedup, radius stays ±1.
- Declined/closed: F2b two-tier decode (main-thread rotateToFill trap), F2c native-res default
  (104 MB/photo), F4 (corpus all-fast), F5 open() async (5 ms; races cost more than the stall).

### 2026-10-02 (cont. 5) — perf2-remaining integrated

- Report read in full; all 5 spot-checked claims verified exactly (4 @Published fields at
  AppState ~128–139, loader forwarding sink at 178–182, sync context-menu Finalize… at
  SessionsPane 144–145, zoomActual/panBy zero callers, AnyView gone — the 1 grep hit is the
  doc comment about removing it). Tests re-run by reviewer: 358/358.
- Findings accepted: **F1** 4-field CanvasState micro-extraction (pan/zoom/cropRect/cropTilt →
  ~35 body evals per drag tick → 2; skip cropMode/cropAspect/tiltFocused/showCroppedPreview);
  **F2** drop loader objectWillChange forwarding + inject loader as environmentObject (3 whole-app
  storms per j/k → 0); **F3** context-menu Finalize… must go through the async summary path;
  **F4** dead zoomActual/panBy deletion (full-res zoom re-decode declined — feature, not perf,
  and main-thread rotateToFill trap); F5 startup + F7 OS-level: nothing left; F6 round-1
  Tier 3 residuals verified fixed.
- Sequencing note: F2/F3/F1 touch AppState/ImagePane/PhotoCullApp — overlaps perf2-interaction's
  domain, so implementation dispatch waits for all three reports to partition disjoint branches.

### 2026-10-02 (cont. 4) — round 2 dispatched: three parallel reviewers

- Parent quick-scan of post-wave-1 code flagged round-2 targets: 4096px-cap decode on j/k miss
  (~4× the 124 ms/2048px baseline), serial ±1 prefetch, thumbnail burst arriving in index (not
  visible-window) order on session open, spinner instead of instant thumbnail placeholder,
  serial same-volume copies in finalize (APFS clonefile candidate), serial ingest, still-synchronous
  `open(date:)`, un-reassessed CanvasState extraction.
- Dispatched 3 read-only reviewers (zai/glm-5.3, tabs in wB, reports to /tmp/perf2/):
  - **perf2-interaction** (wB:p7): j/k latency, thumbnail placeholder, prefetch quality, session-open
    burst ordering, async open(). Report: /tmp/perf2/interaction.md
  - **perf2-io** (wB:p6): clonefile verdict (measured), parallel finalize exports, ingest copy
    concurrency, App Nap / QoS. Report: /tmp/perf2/io.md
  - **perf2-remaining** (wB:p8): pan/zoom body inventory + CanvasState verdict, zoom re-decode
    strategy, startup residuals, churn polish. Report: /tmp/perf2/remaining.md
- Preflight: repo @ 2c74263 clean, `swift build` green (1.76 s), tests 358/358 at last verify;
  reviewers forbidden from GUI/`--check`/installs/repo writes.
- Parent integrates as reports arrive (not in launch order), then plans the implementation wave.

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

### 2026-10-02 (cont. 3) — cleanup

- User confirmed; removed both implementer worktrees (wD perf-view, wE perf-state, clean
  removals — merged branches `perf-view`/`perf-state` kept in git). Pruned completed TODO items.
- README needed no changes: no user-facing behavior claims were affected (finalize now runs in
  background with a toast; ingest card detection moved from launch to ingest-sheet open).

