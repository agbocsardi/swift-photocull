# Luna implementation wave — 2026-10-03

Parent specifies fixes; openai-codex/gpt-6-luna, high reasoning, implements bounded patches. Parent wB:p1 / workspace wB.

## Checklist

- [x] Complete user-approved cleanup; preserve all branches/reports.
- [x] Confirm model/provider with user and verify Luna catalog/auth.
- [x] Trace current loading, rendering, navigation/persistence and Finalize code; separate file ownership.
- [x] Record runtime/input/output/test permissions in AGENTS.md and exact assignments.
- [x] Launch all five independent implementers in committed-base Herdr worktrees, no focus change; startup model argv verified and prompts submitted.
- [x] Review loading patch: correct-photo identity, shared full-key decode, bounded native work, embedded-only stage; fresh native 20-check parent run passed745ecfe; merged f9c7792.
- [x] Review navigation patch: outgoing persistence, same-index session scroll, redundant boundary work; no added debounce; merged a05a917 after fresh 22-check verification.
- [x] Finish render review: corrected isolation/fidelity, ready reuse/backtrack independently verified; merged c2b94a8 after fresh164 checks.
- [x] Review Finalize patch: reserved pair-consistent names, one-time inventory, exclusive owned stages/all-exit cleanup; merged 6cdf6a6 after fresh 35+58 checks.
- [x] Review test-reliability patch: locked collectors, explicit fail-closed suite filter, synthetic concurrent regression; merged da7dea8 after fresh 101 focused checks.
- [x] Integrate all five approved patches sequentially; rerun focused synthetic app/Core checks and preservation regression on combined source.
- [x] Complete reviewed Finalize ownership/app-progress/metadata/native recovery source fixes and effective failures; Sol6fe4f45 merged745e3b3, see 2026-10-03_finalize-safety_TODO.md.
- [ ] Resolve separate ingest naming/content/progress, competing PairRepair and HeadlessCheck diagnostic findings; not covered by Finalize safety acceptance.
- [ ] Add/request native end-to-end metering after caller contracts stabilize; never fabricate paint timings.
- [x] Build and strictly verify an isolated release bundle after integration checks; do not replace or launch installed/running app.
- [ ] User-approved install/live navigation/editing/scroll/placeholder feel test; Finalize remains not cleared.
- [x] User-approved cleanup of all five completed Luna worktrees/tabs; preserve branches/reports and active Finalize safety worker.
- [x] Remove temporary root AGENTS.md after all five implementation patches are complete, reviewed and integration-checked (explicit user request).

## Fixed design / boundaries

- Start from current performance branch, not the rejected step-snappy experiment. Keep immediate sidebar-open semantics: no 70ms timer, no neighbour-session planners to repair because neither ships.
- Fix proven root causes before speculative tuning. Keep 3072 policy and existing exact edit/export primitives; no fused transform, Observation/Metal/vImage migration, custom clone wrapper or LazyHStack reintroduction.
- Loading owns ImageLoader.swift + embedded-only helper in ImagePipeline.swift. Navigation owns AppState.swift + FilmstripPane.swift. Rendering owns ImagePane.swift + a small app-only renderer. Finalize owns Finalize.swift. Reliability owns existing ingest test collectors/harness/main; new checks/scripts have unique names.
- First wave does not claim all large-filmstrip, ingest naming/content comparison, progress ordering, ownership or startup defects solved. Finalize remains not cleared; source merge != updated executable.
- Mandatory bounded generated inputs, no GUI/real library/config/Trash/unfiltered tests; separate caches/build output per child. Parent integrates only committed, reviewed diffs.
- Rendering depends at integration time on loader clearing/tagging the source request correctly; both isolated branches retain existing public call shapes. Reliability runner changes must preserve --finalize-safety-only; other workers use standalone checks rather than editing main.swift.

## Dispatch registry

| Agent | Workspace/pane | Branch | Owned scope | Report |
|---|---|---|---|---|
| luna-load | wN / wN:p1 | fix/luna-image-loading | ImageLoader.swift, ImagePipeline.swift embedded helper; Tests/App/ImageLoadingChecks.swift, scripts/check-image-loading.sh | /tmp/photocull-luna-wave-2026-10-03/loading/report.md |
| luna-nav | wQ / wQ:p1 | fix/luna-session-navigation | AppState.swift, FilmstripPane.swift; Tests/App/NavigationChecks.swift, scripts/check-navigation.sh | /tmp/photocull-luna-wave-2026-10-03/navigation/report.md |
| luna-render | wS / wS:p1 | perf/luna-settled-edits | ImagePane.swift, EditRenderer.swift; Tests/App/EditRenderingChecks.swift, scripts/check-edit-rendering.sh | /tmp/photocull-luna-wave-2026-10-03/render/report.md |
| luna-finalize | wR / wR:p1 | fix/luna-finalize-planning | Finalize.swift; Tests/Core/FinalizePlanningChecks.swift, scripts/check-finalize-planning.sh | /tmp/photocull-luna-wave-2026-10-03/finalize/report.md |
| luna-tests | wP / wP:p1 | fix/luna-test-reliability | Harness.swift, main.swift, three ingest collector sources; Tests/Core/IngestCollectorChecks.swift, scripts/check-ingest-collectors.sh | /tmp/photocull-luna-wave-2026-10-03/reliability/report.md |

## Log

### 2026-10-03 — prepared

- User confirmed Luna implementers after approving cleanup. Five parallel file-disjoint tasks; exact parent designs in /tmp/photocull-luna-wave-2026-10-03/*/assignment.txt.
- Cleanup recorded at 611e182. Known preservation fix is in source, but app bundle unchanged. Remaining safety gates stay explicit.

### 2026-10-03 — dispatched

- Common committed base e2ce9c8. Parsed actual pane/worktree identifiers from Herdr creation JSON with jq; all children started kind pi, openai-codex/gpt-6-luna --thinking high and accepted the exact assignment prompts. All independent tasks submitted without waiting for completions; focus stays on parent.
- luna-load wN:p1 (image request identity/dedup/two native demand workers, embedded-only stage, four thumbnail workers); luna-nav wQ:p1 (outgoing save/error abort, synthetic init, real scroll identity and one thumbnail cache read); luna-render wS:p1 (one running + latest pending exact edit render); luna-finalize wR:p1 (reserved pair names and private/all-exit stage cleanup); luna-tests wP:p1 (locked collectors and explicit suite selection).
- Assignments, create/start/prompt JSON and future reports are under each scope directory in /tmp/photocull-luna-wave-2026-10-03. Release builds and synthetic checks use separate child scratch/cache directories; no shared builds, user data, GUI or Trash.
- Parent integrates only after diff/test review; no worker has merge/release permission. Loader must be integrated before renderer is treated as view-safe. Pure scroll predicates do not certify native layout behavior; parent feel/trace gates remain.
- User explicitly requested removal of temporary root AGENTS.md when the whole wave is done; tracked as an end-of-wave task, not left as permanent project boilerplate.
- Await child completion/blocker messages without polling.

### 2026-10-03 — parent review corrections and first integrations

- luna-tests wP:p1: a627803 returned for top-level exit bypassing defer (three synthetic forensic roots observed). Revised99ff0d8 wraps lifetime in a returning function, asserts exact generated root removal, permits fresh OUT/script-relative invocation and verifies the safety filter. Parent fresh /tmp/photocull-parent-reliability-review-99ff0d8 passed 19 IngestConcurrent +58 safety +21 collector/cleanup +3 invalid-selection checks, zero skips. Merged da7dea8; no production change.
- luna-render wS:p1:41f8cfa returned: default static render inherited MainActor isolation, defeating detached execution. Parent actual-source SIL proved MainActor hop. d3c9f6f explicitly nonisolated, holds ready source identity and observes actual default stages. Parent fresh /tmp/photocull-parent-render-review-d3c9f6f passed158; actual-source SIL now nonisolated. Negative-control temp copy removed nonisolated: regression fails CHECK150 with exit133, demonstrating affinity check detects original bug. No production/temp child source edits by parent. Renderer remains unmerged until loader passes.
- luna-load wN:p1:ae6d65a returned for dropping >32 one-shot mounted-cell thumb requests, detached mutable Job access, silent retained-preview sharp failure, and a fake SwiftUI-module test. Revised9b568b7 retains lightweight queued URLs with native width4, captures immutable preview intent, clears/publishes sharp failure and uses real native frameworks. Parent empty-output check /tmp/photocull-parent-loading-review-9b568b7 failed link: --target Core omitted library product that only existed in worker's older full build. Returned again to build true fresh outputs; require Gate timeout failure (old timeout Bool was discarded). No loader merge yet; await revised completion, no polling.
- luna-finalize wR:p1:4319d99 returned for per-candidate directory enumeration, nonexclusive staging mkdir, non-aliasing orphan case and hardcoded output script. d112717 inventories each distinct directory once (throws on listing failure), uses exclusive Darwin.mkdir0700/retryEEXIST, forces actual orphan collision and isolates tests/scripts. Fresh /tmp/photocull-parent-finalize-review-d112717 passed35 focused +58 safety checks. Merged6cdf6a6; ownership/external writer/promotion-copy failure gaps remain.
- luna-nav wQ:p1:93fe277 returned: save-error test broke both source and destination, so it could pass without flush.58ef85a only breaks outgoing A sidecar, proves B stays loadable/unchanged, and clears loaders/cancels timers on active-session disappearance/finalize completion. Parent fresh /tmp/photocull-parent-navigation-review-58ef85a passed22 real-AppState checks; mergeda05a917. Pure scroll predicates do not prove native centering/animation; UI gate remains.
- Parent builds/scripts use fresh separate OUT dirs; only reviewed synthetic/filtered checks executed. No GUI/real config/user library/Trash/unfiltered tests and no dist replacement. Release app remains unchanged; continue avoiding Finalize. Root AGENTS.md stays temporary until the whole wave is complete and reviewed.
- Final loader script correction745ecfe builds the full library product and makes barrier timeouts fail (not silently complete). Parent brand-new /tmp/photocull-parent-loading-review-745ecfe full release + real SwiftUI/AppKit runner passed20, no skips; loader accepted for merge.
- Final renderer flow correction requested: ready A→B rendering→C pending→A must reuse exact retained ready A, drop obsolete pending, keep actual running flag until B drains and start no redundant A native job. This was missed because ready cache check depended on desiredKey. d3c9f6f remains held until that small regression/change reports.

### 2026-10-03 — reviewed wave complete; integration checked; temporary instructions removed

- luna-render wS:p1 final5441cc9 read/diff-reviewed; parent fresh /tmp/photocull-parent-render-review-5441cc9 passed164. Matching ready-key branch precedes desired-key dedup; stale pending cleared without pretending running work stopped. Combined loader already merged, renderer integrated as c2b94a8. All five dispatched assignments now complete; no child reports outstanding.
- Parent integration source c2b94a8: image-loading20 and edit-rendering164 passed. First shared-OUT attempt then failed navigation standalone compile due duplicate _DarwinFoundation1 PCM paths under /tmp versus canonical/private/tmp (compiler signal11), not an app assertion failure. Failure logs retained. Do not share mixed canonical module-cache paths across standalone/SwiftPM scripts.
- Reran remaining scripts on SAME combined source with separate canonical OUT dirs under /private/tmp/photocull-parent-integrated-c2b94a8: navigation-check22; finalize-check35+58; reliability-check19+58+21+3 invalidCLI. All passed, no skips. Logs in each OUT/check.log; image-loading.log/edit-rendering.log and source-commit.txt in integration root. Full isolated release products also compiled successfully. No unfiltered suite/GUI/real config/library/Trash used.
- Prepared isolated release bundle /private/tmp/photocull-parent-integrated-c2b94a8/release/PhotoCull.app from combined-source release product, original plist/icon/menu image. Ad-hoc codesign and codesign --verify --deep --strict succeeded; executable.sha256/source-commit.txt record identity. Did NOT overwrite dist, installed app, or launch it. Native scroll/placeholder UI and actual request-to-paint latency remain unmeasured.
- User-requested temporary AGENTS.md removed; Git preserves its operational contract in e2ce9c8. Future safety/measurement scope stays in this tracker/docs and requires a fresh bounded assignment, not stale root boilerplate.
- Finalize not cleared: app operation ownership/progress/diagnostic and external-writer/sidecar issues remain follow-ups, not hidden by passing focused checks. Keep avoid-Finalize guidance. At wave completion, five worktrees/tabs retained pending approval; cleanup recorded below.

### 2026-10-03 — user-approved completed-worker cleanup

- Confirmed luna-load/tests/nav/finalize/render idle; all five checkouts clean including untracked/ignored entries, HEADs reachable from performance, reports present outside checkouts.
- Removed Herdr worktree workspaces wN/wP/wQ/wR/wS without force, closing their completed agent tabs. Branches/commits and all reports/verification/release artifacts retained. Removal JSON in /private/tmp/photocull-luna-wave-2026-10-03/cleanup/.
- Remaining PhotoCull checkouts: parent wB and active safety worker wV only. Unrelated website wC/dotfiles wT untouched. Parent root AGENTS.md remains absent; active worker's child-only runtime contract retained. No source/app/data cleanup, release replacement or Finalize use performed.

### 2026-10-03 — remaining Finalize safety source integrated; post-merge verification complete

- Sol corrected6fe4f45 accepted after source review, fresh649 checks, both unchanged original descriptor-reuse probes and effective no-overwrite/early-ingest-completion negative controls. Merged745e3b3; initial516 passing checks did NOT prevent parent returning two proven double-close bugs.
- Fresh merged-source checks: safety649; loading20; exact edits164; reliability106 (includes repeated63 preservation). Separate canonical outputs and signed/strictly verified candidate: /private/tmp/photocull-parent-integrated-finalize-745e3b3/. Full source/evidence/boundaries in safety tracker and authoritative audit.
- Installed/dist/running app not replaced or launched. Native GUI/scroll/placeholder, system Trash, physical cross-volume/crash behavior and controlled request-to-paint remain untested. Continue avoiding Finalize in old app. Ingest identity/naming/progress, competing PairRepair, fail-open HeadlessCheck and large-filmstrip eviction healing remain separate follow-ups.
- Completed safety worker's temporary AGENTS.md archived with report and removed; checkout clean. Owned wV removal awaits approval; preserve branch/report. Parent root remains absent.
