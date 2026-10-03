# Codex performance audit — 2026-10-03

Goal: independent, whole-app performance review; validate earlier claims and prioritize small, safe speedups.
Parent: wB:p1. Model: openai-codex/gpt-6.1-sol, --thinking high. All children kind pi.

## Checklist

- [x] Verify requested model exists, thinking supported, auth ready, Herdr context and clean git tree.
- [x] Freeze baseline 222741b67ab2099e8a8a9d33ab9ab6df479c0302 and unmerged step-snappy e9c6b64d938967628c8ad046d7c3c7b7ac68d39e.
- [x] Dispatch five independent read-only reviewers, no focus changes.
- [ ] Integrate navigation report (including step-snappy review).
- [ ] Integrate render report (including step-snappy review).
- [ ] Integrate images report (including step-snappy review).
- [ ] Integrate I/O/concurrency report.
- [ ] Integrate evidence/test-coverage report.
- [ ] Resolve step-snappy review findings before merging/shipping that branch.
- [ ] Consolidate findings into docs/performance-audit.md; distinguish measured/source-proven/hypothesis.
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
