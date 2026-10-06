# PhotoCull performance audit

## Current assessment — 2026-10-03 (Codex independent review)

**This section supersedes the historical conclusions below.** Five independent
`openai-codex/gpt-6.1-sol --thinking high` reviewers examined frozen baseline
`222741b` and the separate, **unmerged** step-snappy candidate `e9c6b64`.
No GUI, user-library tests, real Trash, or full suite ran in this audit. Parent
read all five reports and spot-verified source and probe artifacts; inspected
probe results are reviewer measurements, not independent parent reruns.

Reports and reproducibility artifacts:
`/tmp/photocull-codex-audit-222741b/{navigation,render,images,io,evidence}/report.md`.
Dispatch/progress: `2026-10-03_codex-performance-audit_TODO.md`. Probe files in
`/tmp` are temporary; preserve approved artifacts before relying on them later.

### Implementation status — first Luna wave complete

Parent-specified fixes, implemented by `openai-codex/gpt-6-luna --thinking high`,
are tracked in `2026-10-03_luna-performance-fixes_TODO.md`. After returning
concrete review defects and rebuilding in fresh parent-owned output:

- `da7dea8`: locked test collectors, fail-closed suite selector, verified cleanup;
  101 focused checks (including 58 preservation), no production callback change.
- `a05a917`: outgoing save/error abort, no-session loader/timer cleanup, real
  session/URL/open-epoch scroll identity, one cache read per cell; 22 model checks.
- `6cdf6a6`: one-time destination inventory/in-run reservations, common archive
  pair suffix, exclusive private stage mkdir and all-exit owned cleanup;
  35 planning + 58 preservation checks. External writers/operation ownership
  and independently induced copy/promotion failure remain unresolved.
- `f9c7792`: demand/prefetch full-key sharing, cold-image clearing, embedded-only
  stage, two native full jobs/four thumb jobs, invalidation guards and terminal
  sharp failure; 20 actual SwiftUI/AppKit model checks. Queued thumbnail URLs
  intentionally stay O(requested cells): dropping at 32 broke one-shot mounted
  requests. Large-filmstrip eviction/virtualization is still a follow-up.
- `c2b94a8`: exact settled edits off-main, one-running/latest-pending work,
  retained source identity and ready-result reuse on reversal; fresh164 checks.
  Parent also verified a failing actor-isolation negative control.

Combined-source checks passed: loading20, edits164, navigation22, planning35+58
preservation, reliability101 (includes the same58 preservation assertions).
These are focused/model checks, NOT a whole-suite or measured UI speedup. One
shared-OUT integration attempt hit a compiler PCM alias conflict between /tmp
and /private/tmp; separate canonical output directories passed the rerun.

A signed/strictly-verified release candidate is prepared at
`/private/tmp/photocull-parent-integrated-c2b94a8/release/PhotoCull.app`, with
source commit and executable hash beside it. **Installed/dist/running app not
replaced or launched; no GUI/real-library/Trash or end-to-end timing run.**
Native scroll/placeholder presentation needs live acceptance. Continue avoiding
Finalize until remaining safety gates are handled. Temporary root `AGENTS.md`
removed as requested; tracked Git history retains the runtime contract.

### Finalize safety follow-up — reviewed and integrated

Sol (`openai-codex/gpt-6.1-sol --thinking high`) completed the parent-designed
native safety protocol on `fix/luna-finalize-safety`; corrected source `6fe4f45`
is merged as **`745e3b3`**. Tracker: `2026-10-03_finalize-safety_TODO.md`.
This status supersedes the first-wave unresolved Finalize gates above, NOT the
separate ingest/repair/diagnostic findings or live release/measurement limits.

- One in-app operation owner spans preparation/consent through actual native
  completion; token/context validation rejects stale summaries and progress.
  Early ingest `p.done` cannot release admission. Mutation, undo and native
  delegate quit gates cover active work. Fresh strict metadata reads precede
  permissive UI persistence; sidecars remain after Finalize.
- Native pinned directory FDs + BSD flock serialize cooperating Finalize runs.
  Identity-checked original claims precede effects; pair members verify together.
  Exclusive native promotions/restores do not overwrite outsiders. Orphans use
  the same protocol. Archive EXDEV fallback copies to a private stage, promotes
  exclusively, then removes only its owned source. Export width is capped at
  two with autorelease pools and stop-on-failure admission, not a measured optimum.
- Durable exclusive recovery plan/progress and original-bearing claims survive
  partial failures; retry fails closed for manual recovery. No recursive inbox
  cleanup, automatic rollback or crash-idempotence claim. Advisory locks/private
  namespace assumptions do not exclude hostile/uncoordinated writers.

Parent initially passed **516 checks** on `2476dc6` but rejected it after two
actual-source descriptor-reuse probes proved initialized constructors closed
FDs twice, potentially closing unrelated I/O. Corrected constructors have one
owner; both unchanged original probes now pass. No user-photo loss established.

Fresh committed-source AND post-merge release runs each passed **649 checks**:
63 preservation,35 planning,385 Core failure/race/EXDEV,39 descriptor,105 app
ownership and22 navigation. The injected EXDEV is inside the real native
move/catch; tests execute copy, exclusive promotion and owned-source unlink,
including actual Foundation copy collision, regular/dangling destination
collisions and native unlink failure after promotion. This is fallback-algorithm
coverage, **not genuine cross-volume filesystem evidence**.

Independent frozen-source negative controls fail with exit133 when RENAME_EXCL
is removed or early ingest terminal progress releases the app gate. Original
probe/control evidence: `/private/tmp/photocull-parent-safety-review-6fe4f45/`.
Post-merge image-loading20, exact edit-render164 and reliability106 also pass
(the reliability run repeats63 preservation checks). Logs/builds use separate
canonical outputs at `/private/tmp/photocull-parent-integrated-finalize-745e3b3/`.
No unfiltered legacy suite, GUI, real config/library/photos/mounts/Trash ran.

**Latest signed/strictly-verified isolated candidate:**
`/private/tmp/photocull-parent-integrated-finalize-745e3b3/release/PhotoCull.app`;
source commit and executable SHA256 beside it. Older first-wave candidate and
reports are retained. **User subsequently authorized updating only
`dist/PhotoCull.app`: its signature and exact candidate hash are verified.**
Previous bundle is preserved as
`dist/PhotoCull.backup-947FB036-CAE2-455C-82F4-4FD6BD207C11.app`; installation
paths/hashes are under the candidate root's `installation/`. No launch/restart
or other installed-copy replacement: do not assume running/other installed
copies have the new safeguards; keep avoiding their Finalize. Copying the
candidate is not native/live destructive-use clearance.
Actual system Trash, physical cross-volume behavior, GUI/delegate integration,
manual crash recovery and native scroll/placeholder feel remain untested.
No controlled input-to-paint, throughput or app-memory measurement added.

Child-only temporary runtime instructions were archived with report then
removed; parent root `AGENTS.md` remains absent. User-approved completed clean
safety worktree/workspace wV removal is complete, without force; branch/report
preserved. Identity/removal JSON is in
`/private/tmp/photocull-finalize-safety-2026-10-03/cleanup/`.

### Live generated-fixture acceptance — 2026-10-06

This supersedes the earlier **no GUI/native Trash run** status for the limited
case below; it does not expand acceptance to all filesystems/camera inputs.
Fixture support c6d340e/25b7c58 was independently reviewed and integrated after
fresh281 startup/operation/navigation checks and four effective negative
controls; merged source also passed a fresh649-check safety rerun. A separate
unique fixture bundle/config isolates ordinary application data/preferences.
Ordinary dist was NOT replaced with test-launch support; never pass its older
binary --fixture-config. Production Finalize/FinalizeSafety/Session/ImagePipeline
are byte-identical to the reviewed dist source745e3b3.

Codex Computer Use's direct command launch aborted during AppKit registration.
Narrow PID/time logs prove inherited sandbox service denials to WindowServer/
LaunchServices before abort; no source/security/service changes were indicated.
Computer Use refused Terminal access, so USER launched the identical command in
ordinary desktop Terminal. Correct fixture identity and six generated photos
appeared; this materially supports the launch-context explanation.

Actual GUI navigation/crop cancellation/centered1:1+2-degree edit/decisions and
Finalize dialog→Cancel passed, with exact original hashes retained. Subsequently
ONE separately directed native Finalize succeeded: **4 archived /2 trashed /
4 exported /1 edited**. Parent reviewed success screenshot/inventory and
independently reran finalized-output validation: archive originals unchanged,
unedited copies identical, edited03 export640×640, sidecar/notes/nested marker
retained and no claims/recovery residue. Parent independently hashed ONLY exact
generated reject04/05 files in native ~/.Trash; both match original bytes.
No broad Trash enumeration, Put Back/delete/empty, retry or cleanup performed.
Reports: `/private/tmp/photocull-gui-nondestructive-XM7LSZ/REPORT.md` and
`/private/tmp/photocull-gui-finalize-xiQTaF/REPORT.md`; tracker:
`2026-10-04_manual-finalize-fixture_TODO.md`. App/evidence remain intact.

**Still untested:** Trash Put Back, real camera RAW, physical cross-volume/crash
behavior, active-bulk quit/progress and large-filmstrip/request-to-paint timing.
The six-photo operation completed before progress was sampled. Grouped AX Help
was stale before decision badges; visible selections/toolbar agreed. Later
completion screenshot captures were blank despite unchanged AX state; initial
completion screenshot valid, origin unresolved. These are limitations, not
silently treated as a full GUI/performance pass or proven app-rendering defects.
No actual-user-library batch or universal data-loss-immunity claim.

User-requested minimal **synthetic RAW-pair** follow-up also passed: native +RAF
pair indicators, one kept pair/one rejected pair, once-only Finalize yielding
6 archivedfiles/2trashed/5unchangedJPEGexports/0edited. Parent independently
verified kept JPEG+RAF archive hashes and unique rejected JPEG+RAF native Trash
hashes. Report: `/private/tmp/photocull-raw-pair-gui-cdotwy72/REPORT.md`.
Opaque generated RAF companions test pairing/file preservation, **not genuine
camera RAW validity/metadata/decoding**. No new source/new worker/deep matrix;
user explicitly prefers stopping unnecessary test expansion. No cleanup/Put Back.

### Original review findings (baseline gates; status above)

1. **Original preservation is urgent.** Finalize recursively deletes its inbox
   session directory despite files the scan omitted: alternate JPEG/RAW
   extensions, dotfiles, unrelated entries and subdirectories. The narrow
   empty-only-removal fix `9fa65c0` is merged as `d039718`: known residue keeps
   its sidecar; kernel rmdir cannot recursively delete late arrivals. Parent's
   fresh release build passed 58/58 synthetic no-Trash checks, and the worker's
   debug binary passed the same focused rerun. Installed/running bundle status
   and the newer isolated release candidate are described above. Late arrivals may still lose the sidecar
   between listing and unlink; external path replacement is not addressed.
   No loss in the user's library is established. **Avoid Finalize for now.**
   Destination probes also fail to reserve names, can split pair suffixes,
   and can plan duplicates. All-exit staging cleanup and operation ownership
   remain separate safety work; the narrow hotfix does not clear these.
2. **Photo identity before speed.** A cold ImageLoader request retains the
   previous image while the new selection's edits change. Fix request/image/
   stage identity and assert reversed decode completions before shipping
   two-stage previews. Demand and prefetch can also decode the same key twice.
3. **Session persistence and pending navigation.** Flush the outgoing session's
   pending last-index persistence before replacing it. Pending A→B→A leaves
   B's debounce alive; same-active clicks also bypass cancellation. Define
   pending-target behavior for focus/filter/edit/modal/close transitions.
4. **Session-scroll identity is not edit revision.** Pending scroll observes
   index alone and misses equal-index switches; edit revision falsely tags
   ordinary photo navigation as a session change. Test identity plus index.
5. **Bound/admit work correctly.** A rejected stale soft publication still
   starts sharp decode; old neighbour planners can acquire a fresh generation
   and filtered adjacency is ignored. Eager filmstrip thumbnail work is
   unbounded; eviction can leave mounted cells without a new request. Keep
   non-lazy layout until its known blank-cell/far-scroll constraints are tested.

### Evidence corrections

- **No preserved controlled end-to-end latency trace.** Prior 415 CHECK results
  exercise Core, not AppState/ImageLoader/SwiftUI. Screenshots after seven
  seconds and qualitative positive feedback are useful smoke/feel evidence,
  not race coverage or measured input-to-correct-photo latency.
- **3072 is a memory/detail policy, not a universal IDCT optimum.** Optimized
  synthetic 6000-wide input: half-size 3000 ~70.6 ms versus 3072 ~180.3 ms;
  6240-wide input: 3120 ~77.4 ms versus 3072 ~110.7 ms. Independent evidence
  probe, 3840-wide input: 1920 ~32.5 ms versus 3072 ~91.4 ms. These warm
  kernel observations depend on input/orientation/platform; no universal
  navigation percentage follows. Cache still has a **16-entry cap**, not ~20.
  Bitmap arithmetic and cache budget are not app RSS/GPU-memory limits.
- **Embedded-only means both ImageIO create-from-image flags explicitly false.**
  Production IfAbsent is a valid fallback for filmstrip thumbnails, but is
  expensive as a mandatory first stage before sharp decode when previews are
  absent. Explicit false/false returned nil at ~0.17–0.20 ms warm in the large
  synthetic probe (first result up to 16.8 ms). Both independent audits found
  the public fixture lacks an embedded preview. The old 49-file survey does
  not establish all future corpora have previews or bound mount contention.
- **Settled edit work is still synchronous on the UI path.** Optimized
  3072×2048 quarter-turn+tilt+crop probes ~73 ms are kernel measurements, not
  app frame timings. A fused single-context prototype ~12 ms changes pixels
  (max channel difference 18/255); no fidelity-preserving replacement is
  established. First consider bounded off-main use of the existing pipeline.
- Exact SwiftUI body counts, zero-latency claims and prefetch/export/ingest
  end-to-end multipliers were not substantiated by preserved UI traces.
  Subscription removal/memoization are source-proven; static subscriber counts
  cannot establish actual body executions. SSD/clone timings are not SD-card
  byte-transfer throughput; reported SD ranges were extrapolations.

### Test/diagnostic repairs and measurement plan

- Three ingest test collectors mutate unchecked-Sendable arrays/values without
  locks while callbacks run concurrently. Protect mutation and snapshot reads;
  do not call the unsynchronized CHECK harness from worker callbacks.
- Require explicit fixtures, suite filters, per-suite counts and skip reasons.
  Isolate Trash-dependent tests; temp-root config does not isolate real Trash.
  The cache concurrentPerform test **is enabled**; loader/app race coverage is
  missing, not disabled. HeadlessCheck can print FAILED/MISSING and exit zero;
  a PNG-written success does not validate requested-image identity.
- Native OSLog/signposts and Observation compile on this toolchain. SwiftUI
  State fails because SwiftUIMacros is missing; XCTest is unavailable and the
  xctrace shim requires full Xcode. Do not migrate observation architecture
  merely because its macro compiles; current StateObject workaround stays.
- Approved next measurement work should use explicit, fail-closed synthetic
  config; never overwrite real config or assume HOME/PC_FIXTURES isolates app
  paths. Build separately in release with debug profiling information and
  record source/executable identity. Add request-keyed monotonic spans for
  input, debounce, planning, state commit, queue/decode, soft/sharp publication
  and settled edits, plus thumbnail/prefetch hit/duplicate/stale-work counts.
- Publication is **data ready, not first paint**. Correlate with compositor/
  visible-marker evidence when available; otherwise state that limitation.
  Measure 30–50 repeats, p50/p95/max and failures on identical cadence/corpus/
  display; separate process/app-cache cold from filesystem-cold. Use native
  log/sample/vmmap now; install no profiling framework or Xcode for this task.

### Ranked implementation scope (proposal, not new approval)

1. Narrow preservation patch reviewed/merged; follow with naming, staging and
   destructive-operation ownership safety fixes before clearing Finalize.
   Rebuild/verify the release bundle before any user feel test; a source merge
   does not replace a running/installed executable.
2. Correct baseline request identity/outgoing persistence and pending debounce/
   scroll/admission defects, with a small controllable MainActor regression
   runner. Prefer explicit embedded-only soft fallback, not generated+sharp
   sequential decoding. Keep step-snappy unmerged until these gates pass.
3. Repair collectors/diagnostics and add minimal native request-path metering.
   Then evaluate bounded off-main settled edits and thumbnail/request work
   using identical synthetic scenarios and user-approved live feel tests.
4. Tune pixel targets/export width only with detail, memory and contention
   evidence. No global Observation rewrite, scheduler framework, custom
   clonefile wrapper, Metal/vImage rewrite or return to LazyHStack.

---

# Historical audit — 2026-10-02

The following records the earlier rationale; numerical UI claims and blanket
optimality statements are not current acceptance evidence (see corrections above).

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

---

# Round 2 — 2026-10-02 (post wave 1+2 merge, commit 2c74263)

Consolidated from three parallel read-only reviews (zai/glm-5.3): `/tmp/perf2/{interaction,io,remaining}.md`.
Earlier parent reported probe re-runs, real-inbox thumbcheck and 358/358 CHECKs.
The original raw distributions/probe provenance are not preserved here; treat these
as reported kernel/smoke observations, not independently reproducible UI speedups.
One reviewer miscounted "356 checks" — parent reported 358.

## Measured facts that reshaped the plan

- **ImageIO IDCT cliff**: decode of a 26 MP JPEG costs ~91 ms at maxPixel ≤ 3072 but ~197 ms at
  3584–4096 (entropy-decode + resample path switch above ~½ native size). The 4096 cap was paying
  the *worst* point on the curve. Native 6240 = 119 ms.
- **`FileManager.copyItem` already APFS-clones** same-volume (0.10 ms / 50 MB; 0 MB physical space
  for 1000 MB logical; clonefile(2) itself 0.08 ms — no win available). Cross-volume (SD ingest)
  clone is impossible (EXDEV). **Clonefile wrapper: rejected by measurement.**
- **Embedded thumbnails**: real inbox corpus = 49/49 files EMBEDDED → filmstrip burst rides the
  0.4 ms path (~45 ms/session). Burst reordering: closed, not needed for this corpus.
- **Parallelism ceilings**: 2-wide prefetch decodes 1.73×; 8-wide cropped exports 3.1–3.7×;
  4-wide ingest copies 3.7–5.8× on SSD (UHS-I card realistically ~1.1–1.4×, UHS-II ~1.5–2.5×).
- **open(date:) main-thread chain ≈ 5 ms warm** (FilePairs 4.2, sidecar 0.1, EXIF 0.2–3).

## Accepted for implementation (wave 3)

| # | Finding | Files | Impact | Effort |
|---|---------|-------|--------|--------|
| A1 | Decode cap 4096→3072 (one token; cache slot 45→25 MB ≈ 20 warm photos) | AppState | −53% j/k miss decode | S |
| A2 | Instant 256px-thumb placeholder in canvas loading branch + crossfade (spinner fallback) | ImagePane | perceived miss latency → ~0 | S |
| A3 | Prefetch 2-wide TaskGroup + inFlight dedup (radius stays ±1) | ImageLoader | both-neighbours-cold 2× faster | S |
| A4 | Drop `imageLoader.objectWillChange` forwarding; inject loader via environmentObject | AppState, PhotoCullApp, ImagePane, ContentView | 3 whole-app storms per j/k → 0 | S |
| A5 | CanvasState micro-extraction: only pan/zoom/cropRect/cropTilt (NOT cropMode/cropAspect/tiltFocused/showCroppedPreview) | AppState, ImagePane, ContentView, PhotoCullApp, new file | ~35 body evals per drag tick → 2 | M |
| A6 | Context-menu "Finalize…" through async summary path (`beginFinalize(date:)`) | SessionsPane, AppState | removes main-thread folder walk | S |
| A7 | Delete dead `zoomActual()`/`panBy()` | AppState | cleanup | S |
| B1 | Parallel cropped-keeper exports (serial dest allocation first; prefix-only moves on failure; temp-name+rename) | Finalize | finalize exports 3.1–3.7× | M |
| B2 | Ingest 2–4-wide copy workers (serial pre-pass: EXIF, safeDestName, skip decision) | Ingest | SSD 3.7–5.8×, UHS-I 1.1–1.4× | M |
| B3 | `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` around ingest/finalize | Ingest/Finalize or AppState | survives App Nap/idle clamp | S |
| B4 | `.fileSizeKey` in scanSource (drop 1 stat/file) | Ingest | ~20 ms per 2000-file card | S |

Wave split (disjoint file domains): **perf2-app** (A1–A7, `Sources/PhotoCullApp/**`) vs
**perf2-io-impl** (B1–B4, `Sources/PhotoCullCore/{Ingest,Finalize}.swift` + tests).

## Rejected this round (with reasons)

- clonefile wrapper — copyItem already clones (measured).
- Filmstrip burst reorder/limit — corpus all-embedded (measured); revisit only if a no-thumb
  corpus appears (thumbcheck probe kept at /tmp/perf2/thumbcheck).
- Full-res / two-tier zoom decode — native is *faster* to decode than 4096 (119 vs 197 ms) but
  104 MB/slot collapses the cache; two-tier re-keys the main-thread CPU edit pipeline on tilted
  photos. Product decision, not perf; has a known trap.
- open(date:) async — 5 ms stall vs re-entrancy/lastIndex races.
- Archive-move/trash/`collisionFreeDestination` parallelism — 0.1 ms ops, racing breaks
  uniqueness. Cross-date parallelism in runMulti — shared dump folder.
- QoS changes to .background/.utility for bulk ops — macOS I/O-throttles background QoS;
  .userInitiated is correct.
- @Observable, Metal/vImage, drawingGroup, LazyHStack, Equatable cells — standing anti-recs;
  Observation's macro compiles on the current toolchain; a migration still needs
  demonstrated benefit. SwiftUI State's separate macro plugin is unavailable.
