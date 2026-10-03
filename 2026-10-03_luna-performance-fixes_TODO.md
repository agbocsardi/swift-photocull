# Luna implementation wave — 2026-10-03

Parent specifies fixes; openai-codex/gpt-6-luna, high reasoning, implements bounded patches. Parent wB:p1 / workspace wB.

## Checklist

- [x] Complete user-approved cleanup; preserve all branches/reports.
- [x] Confirm model/provider with user and verify Luna catalog/auth.
- [x] Trace current loading, rendering, navigation/persistence and Finalize code; separate file ownership.
- [x] Record runtime/input/output/test permissions in AGENTS.md and exact assignments.
- [ ] Launch all five independent implementers in committed-base Herdr worktrees, no focus change.
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
| luna-load | pending | fix/luna-image-loading | ImageLoader.swift, ImagePipeline.swift embedded helper; Tests/App/ImageLoadingChecks.swift, scripts/check-image-loading.sh | /tmp/photocull-luna-wave-2026-10-03/loading/report.md |
| luna-nav | pending | fix/luna-session-navigation | AppState.swift, FilmstripPane.swift; Tests/App/NavigationChecks.swift, scripts/check-navigation.sh | /tmp/photocull-luna-wave-2026-10-03/navigation/report.md |
| luna-render | pending | perf/luna-settled-edits | ImagePane.swift, EditRenderer.swift; Tests/App/EditRenderingChecks.swift, scripts/check-edit-rendering.sh | /tmp/photocull-luna-wave-2026-10-03/render/report.md |
| luna-finalize | pending | fix/luna-finalize-planning | Finalize.swift; Tests/Core/FinalizePlanningChecks.swift, scripts/check-finalize-planning.sh | /tmp/photocull-luna-wave-2026-10-03/finalize/report.md |
| luna-tests | pending | fix/luna-test-reliability | Harness.swift, main.swift, three ingest collector sources; Tests/Core/IngestCollectorChecks.swift, scripts/check-ingest-collectors.sh | /tmp/photocull-luna-wave-2026-10-03/reliability/report.md |

## Log

### 2026-10-03 — prepared

- User confirmed Luna implementers after approving cleanup. Five parallel file-disjoint tasks; exact parent designs in /tmp/photocull-luna-wave-2026-10-03/*/assignment.txt.
- Cleanup recorded at 611e182. Known preservation fix is in source, but app bundle unchanged. Remaining safety gates stay explicit.
