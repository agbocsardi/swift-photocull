# Codex performance audit — 2026-10-03

Goal: independent, whole-app performance review; validate earlier claims and prioritize small, safe speedups.
Parent: wB:p1. Model: openai-codex/gpt-6.1-sol, --thinking high. All children kind pi.

## Checklist

- [x] Verify requested model exists, thinking supported, auth ready, Herdr context and clean git tree.
- [x] Freeze baseline 222741b67ab2099e8a8a9d33ab9ab6df479c0302 and unmerged step-snappy e9c6b64d938967628c8ad046d7c3c7b7ac68d39e.
- [x] Dispatch five independent read-only reviewers, no focus changes.
- [x] Integrate navigation report (including step-snappy review).
- [x] Integrate render report (including step-snappy review); source-verified blockers recorded below.
- [x] Integrate images report (including step-snappy review); probe source/logs inspected.
- [x] Integrate I/O/concurrency report; urgent preservation patch dispatched separately.
- [x] Integrate evidence/test-coverage report; source/capability logs and raw measurement summary inspected.
- [ ] Evaluate urgent finalize-safety-impl patch: empty-only cleanup, residue preservation, dedicated no-Trash tests; integrate/rebuild only after review.
- [ ] Resolve remaining destructive-operation safety findings (unique pair-consistent names/stages, all-exit cleanup, operation ownership) before treating Finalize as cleared for use.
- [ ] Resolve step-snappy review findings before merging/shipping that branch.
- [x] Consolidate findings into docs/performance-audit.md; distinguish measured/source-proven/hypothesis.
- [ ] Propose ranked implementation scope, then delegate any approved edits in isolated worktrees.
- [ ] Clean up owned reviewer tabs after integration and user confirmation.

## Dispatch registry

| Agent | Pane / tab | Scope | Report |
|---|---|---|---|
| codex-perf-navigation | wB:p9 / wB:t9 | keyboard/session/photo latency, async request scheduling, persistence | /tmp/photocull-codex-audit-222741b/navigation/report.md |
| codex-perf-render | wB:pA / wB:tA | SwiftUI layout, filmstrip/sidebar, canvas/render, scaling | /tmp/photocull-codex-audit-222741b/render/report.md |
| codex-perf-images | wB:pB / wB:tB | ImageIO, transforms, GPU/native options, caching/peak memory | /tmp/photocull-codex-audit-222741b/images/report.md |
| codex-perf-io | wB:pC / wB:tC | finalize/ingest, thread bridges, bounded concurrency, filesystem safety | /tmp/photocull-codex-audit-222741b/io/report.md |
| codex-perf-evidence | wB:pD / wB:tD | benchmarks, test coverage, safe profiling plan, startup/build | /tmp/photocull-codex-audit-222741b/evidence/report.md |

## Runtime / provenance

- Original checkout: /Users/agbocsardi/Documents/1-projects/swift-photocull (performance).
- Frozen committed source: /tmp/photocull-codex-audit-222741b/source (git archive, not a mutable worktree).
- Pending step-snappy frozen source: /tmp/photocull-codex-audit-222741b/pending-step-snappy; diff: /tmp/photocull-codex-audit-222741b/step-snappy.diff.
- Shared detailed contract: /tmp/photocull-codex-audit-222741b/contract.md; child assignments in their report directories.
- Swift 6.4, arm64 macOS; package macOS 14 minimum / Swift language mode 5; no new dependencies/setup.
- Read-only public fixture verified: /Users/agbocsardi/Documents/1-projects/photocull/tests/fixtures/20240503-DSCF2771.jpeg (189013 bytes).
- Only writes allowed: each child's own report/probe/module-cache directory. Source/repo/real library/config/Trash untouched. Edit tool disabled at launch; shell/write limited by assignment contract, not claimed to be an OS sandbox.
- No shared builds/test runs, GUI, --check, --snapshot, mounts, installs, or user-library scans. Small synthetic optimized swiftc probes permitted; report warm-cache/concurrent-machine caveats.

## Log

### 2026-10-03 — dispatched

- User explicitly requested Codex GPT 6.1 Sol high-reasoning review agents. Model catalog confirms exact ID; auth check returns ready. All five started and prompted successfully with --thinking high --exclude-tools edit.
- Fresh eyes: prior audits are context, not dogma. Ask for source-backed paths, bounded measurements, minimal/native solutions, explicit tradeoffs, no speculative body-count/speedup promises.
- step-snappy-impl completed during dispatch (2a970d2, 4cc796a, 4a31ff4, e9c6b64; 415 checks reported). Its unmerged implementation frozen separately for reviewers; do not ship until evaluated. Worktree wK retained. Previously merged step-opens worktree wJ also retained pending cleanup confirmation.
- Reports delivered via one completion message to parent pane wB:p1. Await reports without polling.

### 2026-10-03 — render report integrated; step-snappy stays unmerged

- codex-perf-render (wB:pA) delivered render/report.md, eight findings; parent read report and spot-verified frozen baseline/pending source plus probe-results.txt. Synthetic optimized quarter+tilt+crop median 72.92 ms (3072×2048); NOT an app-frame latency measurement and not independently re-run here.
- Confirmed merge blockers in pending: F3 scroll uses edit revision, misses same-index session switches/initial positioning; F5 A→B→A leaves B's timer pending, same-active click bypasses cancellation; F7 old neighbor preflight captures a fresh generation at admission, uses unfiltered adjacency, and soft-stage publication rejection doesn't exit the outer sharp-decode task. Need correction/test design after other reviews land.
- Confirmed baseline F4 current CGImage is retained on cache miss while selected-photo edit state changes; intended placeholder branch can be bypassed and old pixels edited with the new photo's edits. Pending narrows but doesn't eliminate it.
- Accepted opportunities for consolidated plan: F2 redundant memo-key flags + bounded off-main settled edits with existing pipeline; F1 large-session filmstrip mounting/request fanout and eviction misses that don't restart .task; F6 three touching LRU reads per successful cell body; F8 sidebar rows' broad subscription (measure before scheduling).
- Correct prior claims: publisher sends/static observers do not prove exact SwiftUI body counts; a generation guard cannot interrupt ImageIO already running; 70 ms debounce adds single-step delay (not established as masked); current cache entry cap remains 16 despite the old '~20 warm photos' claim.
- No production code changed or merged. Await navigation/images/io/evidence reports; then consolidate overlapping fixes and prioritize.

### 2026-10-03 — I/O and navigation reports integrated; urgent safety work dispatched

- codex-perf-io (wB:pC): report read in full. Parent verified shipped Finalize recursive cleanup at 218–222 against FilePairs omission rules; successful finalize can permanently remove unselected duplicate-extension originals, unrelated files and concurrent arrivals. User advised to avoid Finalize; no actual library loss established.
- Safety implementer dispatched: finalize-safety-impl, wM:p1 / wM:t1, workspace wM, branch fix/finalize-preserve-originals, worktree /Users/agbocsardi/.herdr/worktrees/swift-photocull/fix-finalize-preserve-originals, base ee90804, Codex gpt-6.1-sol high. Scope: Finalize empty-only cleanup + retain residue/sidecar + independent synthetic safety tests; no real Trash/user-data tests, no wider refactor. Assignment /tmp/photocull-codex-audit-222741b/finalize-safety-assignment.txt.
- I/O probe.log inspected: duplicate planned names and mismatched pair suffixes, size-only false identity, competing repair targets, four concurrent progress callbacks and nonmonotonic copied snapshots. These are controlled helper/contract probes, not throughput data. Source confirms name probes reserve nothing, stage cleanup only covers encode failures, core-count exports ignore native working set, and Task+semaphore bridges block cooperative callers. Queue these separately; immediate empty-only patch does not resolve all safety findings.
- codex-perf-navigation (wB:p9): report read; control-flow probe outputs inspected (mock decoder, NOT ImageIO timing). Baseline retains wrong-photo pixels, duplicates prefetch+foreground, ignores useful superseded results; pending still starts full decode after rejecting stale soft publication. Source verifies outgoing persistence task resolves the current session and open() does not flush before replacement—normal switching can lose remembered index.
- Navigation/render corroborate pending debounce backtrack, filtered/stale neighbor admission and revision/index scroll defects. Other pending target-policy races include editing/closing/filtering/modals before timer fires. No-op boundary navigation repeats metadata work; request coordination and metadata reuse remain opportunities. Uppercase skip-decided key dispatch issue noted for separate correctness follow-up.
- No app-source changes merged. Remaining independent reports: images, evidence; urgent safety patch also awaited.

### 2026-10-03 — images report integrated

- codex-perf-images (wB:pB): full report read; parent inspected explicit-false helper source, thumbnail results, decode grid, edit results and extra-results. Reports corroborate wrong-photo retention, stale sharp-stage admission, duplicate request work and core-count native export memory risk.
- Native embedded-only helper is the smallest viable preview improvement: explicitly false BOTH CreateThumbnailFromImageAlways and CreateThumbnailFromImageIfAbsent, preserving transform/maxPixel/cache-immediately; missing embedded result -> full decode directly. Corrected large-file probe warm medians 0.17–0.20 ms nil, first sample up to 16.8 ms (NOT a hard deadline). Earlier omitted-flags probe did synthesize full-image fallback and is not valid embedded-only evidence. Public test fixture has no embedded thumb.
- Sequential fallback preview+full regresses no-embedded requests: synthetic 6240 direct3072 110.7 ms vs sequential276.5 ms; no global UI speed promise. Preserve preview/full/error identity/quality semantics and share selected cached thumb where practical.
- Fixed3072 claim corrected: synthetic6000 half3000 70.6 ms vs3072 180.3 ms; 6240 half3120 77.4 ms vs3072 110.7 ms; orientation alters cost. Keep cap as a memory policy until fit/backing-scale/detail demand is measured; share any future target selection with prefetch.
- Fused native quarter+tilt+crop prototype median11.6 ms vs sequential72.8 ms on one synthetic crop, but mean channel difference0.25/255 and max18/255. NOT approved as a replacement; bounded off-main existing pipeline is the lower-risk first change.
- Cache stride/backing caveats confirmed in probe: use bytesPerRow*height as better bookkeeping, not RSS; cap16 stays authoritative and lone oversized-entry exception documented. Invalidation weaknesses latent (no production callers), not mislabeled active defects.
- Worker disclosed temporary corpus ceiling overrun (~157MB) then corrected/removes duplicate; present corpus under128MB, no user-data or source writes.
- Await evidence report and finalize-safety implementation. All pending app changes remain unmerged.

### 2026-10-03 — evidence report integrated; all five reviews consolidated

- codex-perf-evidence (wB:pD): full report read. Parent checked three unlocked ingest callback collectors against production concurrent callback dispatch, HeadlessCheck FAILED/MISSING -> zero control flow, Core-only test-target dependency, raw pipeline-summary, Observation/signpost probe sources and compiler/capability logs. Did not rerun probes or launch the app.
- Optimized bounded evidence probe independently corroborates input-dependent ImageIO cliffs and absent-embedded fallback expense (synthetic3840: half1920 mean32.5ms,3072 mean91.4ms; generated256 mean63.9ms). Six retained repeats after first discarded are not p95/p99 or app-frame data.
- Evidence correction: no preserved controlled end-to-end timing; previous CHECK totals cannot validate app-layer pending changes. Cache concurrency loop is enabled (missing loader coverage != disabled tests). Observation compiles; only specific SwiftUI macro plugin failure verified. Native signposts available; XCTest/xctrace unavailable in selected CLT environment.
- Updated docs/performance-audit.md with authoritative current section, five-review provenance, source-proven correctness gates, measured-kernel caveats, test/diagnostic repairs and ranked proposal. Historical rationale retained but explicitly superseded; removed blanket current macro-incompatibility claim.
- Proposed next scope: original-preservation safety first; request identity/outgoing persistence and debounce/scroll/stale-admission app regressions next; hermetic collector/diagnostic fixes and native metering; bounded existing-pipeline settled edits/thumbnail work only with focused acceptance. No global pixel-cap change, Observation rewrite, scheduler framework or fidelity-changing fused transform approved.
- Remaining child: finalize-safety-impl, wM:p1; await completion, review diff and dedicated no-Trash regressions. No production code merged or release rebuild performed; step-snappy stays unmerged. Reviewer tabs/worktrees retained pending user cleanup approval.
