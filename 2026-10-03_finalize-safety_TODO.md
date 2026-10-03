# Remaining Finalize safety pass — 2026-10-03

## Checklist

- [x] User requests Finalize safety fixes and Luna dispatch; reuse selected openai-codex/gpt-6-luna --thinking high.
- [x] Trace current Core/AppState/callers and reconcile historical audit with integrated naming/staging/empty-only fixes.
- [x] Specify shared operation ownership, stale-state/progress protection, metadata retention, strict destructive reads, source claims/path validation, recovery records and bounded native exports.
- [x] Create isolated Herdr worktree from clean committed 130f040; record exact temporary runtime contract ONLY in child's AGENTS.md, not parent root.
- [x] Start luna-finalize-safety / wV:p1, submit exact assignment, record readiness/acceptance.
- [ ] Review committed diff, native identity/claim/recovery boundaries and effective failure injection; return defects instead of accepting worker counts.
- [ ] Independently run focused synthetic Finalize/Core/AppState and prior navigation/planning/preservation checks from fresh separate canonical outputs; no Trash/GUI/user inputs.
- [ ] Integrate reviewed source, update authoritative audit and first-wave tracker with actual evidence and remaining limits.
- [ ] Rebuild/verify isolated candidate only after integration. Installed/dist/running app unchanged unless user authorizes replacement.
- [ ] Remove child's temporary AGENTS.md after review; close/remove ONLY owned worktree after user approval, preserve commits/report.

## Dispatch

- Parent wB:p1 / wB; child luna-finalize-safety / wV:p1 / wV:t1 / workspace wV.
- Branch fix/luna-finalize-safety; checkout /Users/agbocsardi/.herdr/worktrees/swift-photocull/fix-luna-finalize-safety.
- Base 130f04024889c5af23b7cf92d49d2a5690ec710e; parent clean at creation. No focus switch.
- Assignment: /private/tmp/photocull-finalize-safety-2026-10-03/assignment.txt. Exact inputs/runtimes/preflight/outputs/permissions are also in child-only AGENTS.md.
- Create/start/prompt JSON, worker outputs, final report: /private/tmp/photocull-finalize-safety-2026-10-03/.
- Worker allowlist: Core Finalize.swift/Session.swift/optional FinalizeSafety.swift; app AppState.swift/PhotoCullApp.swift/optional operation helper; unique Core/App checks/script; existing focused preservation/planning checks. No worker merges, real-data tests, app replacement or further delegation.

## Fixed safety policy

- Sidecars are not garbage: retain them rather than an enumerate/unlink race. Empty sidecar-only inbox folders may remain; report this deliberate tradeoff.
- Claim and verify original identities before destructive effects, not lstat-then-trash a mutable original URL. Native pinned directory/exclusive claims/no-overwrite restores; preserve original-bearing claim folders on error.
- Recovery record blocks silent retries after partial failure/crash; initially manual recovery, no crash-idempotence/automatic rollback promise.
- Shared in-app gate and cooperating Finalize advisory lock are not immunity to malicious/uncoordinated writers. Parent reviews exact supported boundary before clearing Finalize.
- Fixed export cap two/autoreleasepool is conservative policy; no invented throughput/latency/peak-memory claim.
- Existing first-wave candidate remains uninstalled; keep avoiding Finalize until review and integration checks finish.

## Log

### 2026-10-03 — prepared and dispatched

- Clean parent source at130f040. Confirmed Herdr wB:p1/wB and Luna OAuth readiness; parsed actual child identity from create JSON. One bounded worker, not a new performance wave.
- Read all current Finalize and AppState call paths, Session, scan/library, native app delegate, focused regressions and historical I/O audit. Existing naming/staging safeguards retained. Root cause gaps: separate mutation flags; stale summaries/progress and undo targets; sidecar deletion race; mutable original URLs; partial-pair retry; cooperative semaphore bridge/core-count export width.
- Parent designed concrete fixes and per-boundary synthetic regressions. No GUI, mounts, real config/library/photos/Trash/unfiltered tests authorized. Child's temporary AGENTS.md is deliberately untracked and not part of integration; parent root stays absent per previous user cleanup request.
- Agent startup confirmed interactive readiness and exact argv pi --provider openai-codex --model gpt-6-luna --thinking high; prompt accepted. Identity luna-finalize-safety / wV:p1, base130f040. create.json/start.json/prompt.json retained in dispatch root. Parent awaits one completion/blocker report without polling.
- User approved meantime cleanup: removed the five completed, integrated and fully clean first-wave worktrees/tabs (wN/wP/wQ/wR/wS), no force; retained branches/reports/artifacts. Active safety workspace wV, its untracked runtime AGENTS.md, parent wB and unrelated workspaces untouched. This worker's cleanup remains gated on completion/review and user approval.
