# Luna implementation wave — 2026-10-03

Parent specifies fixes; openai-codex/gpt-6-luna, high reasoning, implements bounded patches. Parent wB:p1 / workspace wB.

## Checklist

- [x] Complete user-approved cleanup; preserve all branches/reports.
- [x] Confirm model/provider with user and verify Luna catalog/auth.
- [x] Trace current loading, rendering, navigation/persistence and Finalize code; separate file ownership.
- [x] Record runtime/input/output/test permissions in AGENTS.md and exact assignments.
- [x] Launch all five independent implementers in committed-base Herdr worktrees, no focus change; startup model argv verified and prompts submitted.
- [ ] Review loading patch: correct-photo identity, shared full-key decode, bounded latest-demand work, embedded-only soft stage.
- [ ] Review navigation patch: outgoing persistence, same-index session scroll, redundant boundary work; no added debounce.
- [ ] Review render patch: effective-input key, single-running/latest-pending existing-pipeline rendering, stale suppression/fidelity.
- [ ] Review Finalize patch: reserved pair-consistent destinations, unique owned stage files, all-exit cleanup.
- [ ] Review test-reliability patch: locked collectors, explicit fail-closed suite filter, synthetic concurrent regression.
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
