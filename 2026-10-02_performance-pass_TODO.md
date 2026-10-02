# Performance pass TODO

Goal: make PhotoCull snappy end to end. Reported pain: crop + tilt interactions lag.
Branch: `performance`. Audit report: `docs/performance-audit.md`.

## Tasks

- [ ] Create `performance` branch
- [ ] Parallel sub-agent audit (4 reviewers, zai/glm-5.3-flash)
  - [x] hotpath: crop/tilt/zoom/pan per-frame costs (ImagePane, CropOverlay, AppState, ImageLoader)
  - [x] pipeline: decode/rotate/crop/encode + caches (ImagePipeline, Exif, build flags)
  - [ ] render: SwiftUI re-render topology (AppState @Published granularity, filmstrip, overlays)
  - [x] render: SwiftUI re-render topology (AppState @Published granularity, filmstrip, overlays)
  - [x] misc: main-thread IO, ingest/finalize responsiveness, KeyMonitor, startup
- [x] Integrate findings into ranked audit doc → `docs/performance-audit.md`
- [ ] Implement top fixes (ranked by impact/effort)
- [ ] Re-verify: 348 checks pass, snapshot renders, live crop/tilt feels snappy
- [ ] Update README/notes if user-facing behavior changed

## Log

### 2026-10-02

- Branched `performance` off `main` (was 8 commits ahead of origin, tree clean).
- Parent quick-scan already flagged: `ImagePane.displayImage` computed property re-runs the
  full CPU edit pipeline on every body evaluation (every drag/pan/zoom frame, main thread),
  plus `.shadow(radius: 12)` blurred per frame over the full-size photo.
- Launched 4 read-only review sub-agents in parallel (zai/glm-5.3-flash).
