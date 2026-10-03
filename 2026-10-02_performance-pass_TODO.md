# Performance pass TODO

Goal: make PhotoCull snappy end to end. Reported pain: crop + tilt interactions lag.
Branch: `performance`. Audit report: `docs/performance-audit.md`.

## Tasks

- [x] Round 2: integrate three reviewer reports (interaction / io / remaining) into audit
- [x] Round 2: dispatch implementation wave from consolidated findings
- [x] Round 2: evaluate both implementer reports (diff review, risky-spot checklist, merge)
- [x] Round 2: verify (build + full test suite + `--check` + snapshot) and hand off for live feel test
- [x] **Live feel test (round 2): j/k snappiness, session open, pan/zoom, finalize speed — fresh dist/PhotoCull.app built 21:48** — user: "performance is great!"
- [x] Live crop/tilt feel test (round 1, confirmed in cont. 3 log)
- [x] CanvasState extraction — landed in wave 3 (perf2-app, commit 4ac83ed)
- [x] Feature: sidebar step-opens-session — evaluated, merged (2a96314→merge), 415/415, snapshot OK, dist rebuilt. Worktree wJ kept until user tries it
- [ ] Step-snappy wave: evaluate step-snappy-impl (A two-stage decode, B debounced step-open,
      C non-animated session scroll, E neighbor-session prefetch), merge, verify, rebuild dist
- [ ] User live-test: session stepping feel

## Log

### 2026-10-02

- Branched `performance` off `main` (was 8 commits ahead of origin, tree clean).
- Parent quick-scan already flagged: `ImagePane.displayImage` computed property re-runs the
  full CPU edit pipeline on every body evaluation (every drag/pan/zoom frame, main thread),
  plus `.shadow(radius: 12)` blurred per frame over the full-size photo.
- Launched 4 read-only review sub-agents in parallel (zai/glm-5.3-flash).

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

### 2026-10-02 (cont. 7) — perf2-io integrated; all three in; wave 3 dispatched

- Report verified: copyItem sites + detached-QoS claims grep-confirmed; suite re-run by parent →
  **358/358** (reviewer's "356" was a miscount). FAT32 fixture already detached by reviewer.
- Clonefile hunch killed by measurement (copyItem already APFS-clones). Accepted: **B1** parallel
  cropped exports (3.1–3.7× measured), **B2** ingest 2–4-wide workers (SSD 3.7–5.8×, UHS-I
  1.1–1.4× realistic), **B3** beginActivity one-liner, **B4** fileSizeKey nit.
- Round-2 section appended to docs/performance-audit.md (measured facts, accepted A1–A7/B1–B4,
  rejected list). Committed before dispatch so implementers branch from it.
- Implementation wave 3 = two worktree agents (**glm-5.3-flash**, per user) on disjoint file domains:
  - **perf2-app-impl** (wH:p1, branch `perf2-app`, worktree ~/.herdr/worktrees/swift-photocull/perf2-app):
    A1 3072 cap · A2 instant thumb placeholder + crossfade · A3 2-wide prefetch + inFlight · A4 loader
    envObject (kill forwarding) · A5 CanvasState 4-field extraction (zoom methods move onto it) ·
    A6 async context-menu finalize · A7 dead-code deletion. Ordered steps, suite green between each.
  - **perf2-io-impl** (wG:p1, branch `perf2-io`, worktree ~/.herdr/worktrees/swift-photocull/perf2-io):
    B1 three-phase finalize (serial dest allocation → parallel exports to .tmp+rename → serial
    prefix-only moves, fail-fast preserved) · B2 two-phase ingest (serial EXIF/names/skips →
    4-wide copies) · B3 beginActivity in core · B4 fileSizeKey · new tests for prefix-failure,
    multi-crop determinism, mixed skip/collision ingest, no .tmp leftovers.
- Reviewer tabs (wB:t6/t7/t8) closed after integration, per user. Worktrees verified at 05c0058,
  clean, before agent start.

### 2026-10-02 (cont. 8) — perf2-app-impl evaluated & merged

- Reported 2e8446f + 4ac83ed on `perf2-app`. Parent read the FULL diff (all 7 files).
- Checklist results: forwarding sink + cancellables + `import Combine` gone · currentMaxPixel 3072
  with cliff comment · zoomActual/panBy deleted · beginFinalize(date:) delegates from current variant ·
  all ~15 canvas mutation sites moved (open/setIndex/loadCurrent/enter/cancel/reset/commit/clear/
  nudge/constrain/arrows/hjkl/zoom keys) · CropOverlay binds $canvas.cropRect · --crop hook via
  app.canvas · env injections for loader+canvas at WindowGroup root · placeholder confined to
  loading branch with spinner fallback · prefetch TaskGroup retires inFlight on stale/failed paths.
  Migration completeness proven by construction: the 4 @Published fields left AppState, so any
  missed reader would fail the build — build clean.
- Parent verification: swift build clean · 358/358 · runtime snapshots render (3024×1896, plain +
  --crop) — catches missing environmentObject injections the suite can't.
- Merged --no-ff onto `performance` (d0b9d21 range), suite re-run green post-merge. Pre-existing
  ContentView weak-capture warning verified present on baseline 05c0058 — not a regression.
- Awaiting perf2-io-impl; will merge + full battery (build, suite, --check, snapshots, dist) after.

### 2026-10-02 (cont. 9) — perf2-io-impl evaluated: revision requested

- Reported e67e5bf + 7225785 + 524194c + de1eb84 on `perf2-io` (404/404, 9 green runs claimed).
  Parent re-ran suite: 404/404 confirmed. Full diff read.
- Approved: three-phase finalize structure, tmp+rename with error-path cleanup, rolling width
  cap at activeProcessorCount, ProgressBox lock discipline, ingest phase-1 planning (EXIF/names/
  skips serial) + 4-wide copies with drain-on-error, beginActivity guards in core, fileSizeKey
  pass-through, 46 new tests incl. collision/skip/progress/re-run coverage.
- BLOCKER found by review — phase-1/2 side effects break fail-fast prefix semantics vs pre-wave-3:
  rejects after the failure index get pre-trashed, unedited keepers pre-cloned to dump, later
  cropped jobs pre-exported. Old contract: failing at pair k leaves k..N fully untouched;
  re-runs after the new behavior would mint _2 dump duplicates. Child documented part of this
  (dump clones) and pinned it in a test — honest, but not mergeable as-is.
- Revision sent to warm agent: phase 1 becomes PURE PLANNING (no side effects; dir creates stay
  up-front as in old code); trash + clone-dumps move to phase-3 walk at their original pair
  positions; tests updated (S0003 not dumped on failure, reject-after-failure stays in inbox,
  clean re-run names); fix misindented brace. Awaiting revision report before merge.

### 2026-10-02 (cont. 10) — io revision verified, both branches merged, full battery green

- Revision 05958aa reviewed in full: phase 1 pure planning (classify + allocate only), phase 2
  stages exports to .tmp (worker removes tmp on error), phase 3 performs every ordered effect
  (trash / clone / promote-rename / archive) with staged-tmp cleanup of unprocessed pairs on the
  fail-fast break. Child's staging extension was correct — a completed later export must not
  land in the dump either. Tests updated: dump-after-failure holds only the prefix, reject-
  after-failure stays in inbox, re-run yields clean names, tmp hygiene both paths.
- Parent verification: build clean, 415/415 ×2 in worktree → merged --no-ff onto `performance`
  → build + 415/415 on merged → real-library `--check` green (decode 2048px 119 ms, LRU intact,
  finalize planning OK on 81-pair session) → snapshots render (plain + --crop) → release bundle
  rebuilt (dist/PhotoCull.app 21:48).
- Workspaces wH (perf2-app) / wG (perf2-io) kept until user confirms the live feel test;
  branches `perf2-app` / `perf2-io` stay in git.

### 2026-10-03 — perf round 2 confirmed by user; worktrees cleaned; feature ask dispatched

- User confirmed the live feel test — round 2 performance pass CLOSED. Removed both implementer
  worktrees (wH perf2-app, wG perf2-io, clean removals; branches kept in git).
- Feature ask: in pane 1, arrows/j/k stepping onto a session should open it (no Enter needed).
  Parent scout: `moveCursor(_:)` (AppState ~591) is the single step primitive for arrows+j/k
  when pane 1 focused; init/filter cursor writes must stay non-opening; `open(date:)` ≈5 ms +
  generation-cancelled decodes make rapid stepping safe by design.
- Dispatched **step-opens-impl** (glm-5.3-flash, wJ:p1, branch `feature/step-opens-session`):
  open target in moveCursor when `!= activeDate`, keep Enter/Tab/click semantics unchanged,
  README keyboard-table update, WHY comment. DoD: build + 415/415, AppState.swift + README only.

### 2026-10-03 (cont. 2) — step-snappy wave dispatched

- User reports residual lag stepping sessions (post step-opens). Parent diagnosis from round-2
  measurements: per step = 150-cell filmstrip teardown/rebuild + animated scrollTo + thumbnail
  burst + cold 91 ms decode with spinner (placeholder never fires on cold sessions — ImagePane
  doesn't observe ThumbnailStore) + zero warming of neighbor sessions.
- Dispatched **step-snappy-impl** (glm-5.3-flash, wK:p1, branch `perf/step-snappy`, 3 files:
  ImageLoader/AppState/FilmstripPane):
  **A** two-stage decode (256px stage via ImagePipeline.thumbnail — 0.4 ms embedded — published
  immediately, full 3072 after; stage-1 not cached; no-embed trade-off documented);
  **B** 70 ms trailing debounce on step-opens (cursor still moves instantly; flush points in
  open()/Enter/finalize/ingest; direct opens never debounced);
  **C** session-switch scrollTo without animation (ViewState lastRev trick; in-session nav
  stays animated);
  **E** neighbor-session prefetch of the remembered photo (off-main sidecar+scan+size, maxPixel
  matched to loadCurrent's target so cache keys align; generation check self-cancels).
- Awaiting report; then parent review → merge → build + 415/415 + snapshot + dist rebuild →
  user live-test.

### 2026-10-03 (cont.) — step-opens evaluated, merged, shipped

- b71efdb reviewed: both moveCursor branches open on `!= activeDate`, Enter/Tab/click untouched,
  README rows tight, WHY comments real. 10 lines of logic — minimal diff, exactly to spec.
- Parent verification: build + 415/415 in worktree, merged --no-ff onto `performance`, 415/415
  on merged, snapshot renders, dist/PhotoCull.app rebuilt.
- Worktree wJ kept until user confirms the feel; branch `feature/step-opens-session` in git.
