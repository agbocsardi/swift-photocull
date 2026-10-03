# Luna implementation wave — 2026-10-03

Parent specifies fixes; openai-codex/gpt-6-luna, high reasoning, implements bounded patches. Parent wB:p1 / workspace wB.

## Checklist

- [x] Complete user-approved cleanup; preserve all branches/reports.
- [x] Confirm model/provider with user and verify Luna catalog/auth.
- [x] Trace current loading, rendering, navigation/persistence and Finalize code; separate file ownership.
- [x] Record runtime/input/output/test permissions in AGENTS.md and exact assignments.
- [x] Launch all five independent implementers in committed-base Herdr worktrees, no focus change; startup model argv verified and prompts submitted.
- [x] Review loading patch: correct-photo identity, shared full-key decode, bounded native work, embedded-only stage; fresh native 20-check parent run passed745ecfe.
- [x] Review navigation patch: outgoing persistence, same-index session scroll, redundant boundary work; no added debounce; merged a05a917 after fresh 22-check verification.
- [ ] Finish render review: corrected isolation/fidelity independently verified; final ready-result reuse/backtrack correction pending before merge.
- [x] Review Finalize patch: reserved pair-consistent names, one-time inventory, exclusive owned stages/all-exit cleanup; merged 6cdf6a6 after fresh 35+58 checks.
- [x] Review test-reliability patch: locked collectors, explicit fail-closed suite filter, synthetic concurrent regression; merged da7dea8 after fresh 101 focused checks.
- [ ] Integrate approved patches sequentially; rerun focused synthetic app/Core checks and preservation regression.
- [ ] Complete follow-up operation ownership/progress/diagnostic gates before clearing Finalize.
- [ ] Add/request native end-to-end metering after caller contracts stabilize; never fabricate paint timings.
- [ ] Rebuild release bundle only after integration review and focused checks; request authorized live feel test.
- [ ] Clean newly owned worktrees/tabs only after user approval and review.
- [ ] Remove temporary root AGENTS.md once the whole implementation wave is complete and reviewed (explicit user request).

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
