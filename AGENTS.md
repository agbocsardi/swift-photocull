# PhotoCull agent runtime and permissions

## Implementation wave — 2026-10-03

Parent: Herdr wB:p1, workspace wB. User selected **openai-codex/gpt-6-luna, high reasoning** implementers; parent specifies fixes, reviews diffs, and integrates. Each editor uses its own Herdr worktree. Do not change this file, the parent checkout, another worker checkout, or shared tracking docs from a child.

### Authoritative inputs

- Committed checkout/source and `docs/performance-audit.md` are authoritative. Do not merge/cherry-pick `perf/step-snappy`; its debounce and neighbour-session warming are unapproved experiments.
- Independent reports (read-only): `/tmp/photocull-codex-audit-222741b/{navigation,render,images,io,evidence}/report.md`.
- Parent design/assignments: `/tmp/photocull-luna-wave-2026-10-03/`. Each child receives an exact assignment and file allowlist there.
- No personal photographs, real libraries or external fixtures are required. Generate all inputs inside the child's dedicated output directory. Worktrees do not copy ignored data; missing fixture is not permission to search the user's home.

### Runtime/preflight

Swift 6.4, arm64 macOS, package macOS 14 minimum, Swift language mode 5. Current CLT lacks SwiftUI State macros/XCTest/xctrace; keep StateObject/ViewState and the existing minimal executable/standalone checks. Observation compiles but no observation migration is authorized. Native Foundation/SwiftUI/CoreGraphics/ImageIO/OSLog only; no dependencies/install/toolchain changes.

Verify `test "$HERDR_ENV" = 1`, `git status --short`, `swift --version`, and read the assigned files/callers before edits. Commit changes with WHY on your assigned branch, never merge into the parent.

### Exact build isolation

Use OUT equal to the dedicated absolute directory in your assignment (not another worker's directory):

```sh
mkdir -p "$OUT"/{build,cache,config,security,module-cache,clang-module-cache}
CLANG_MODULE_CACHE_PATH="$OUT/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache" \
swift build --scratch-path "$OUT/build" --cache-path "$OUT/cache" \
  --config-path "$OUT/config" --security-path "$OUT/security" -c release
```

Build only in your worktree with these isolated outputs, never shared `.build`/dist. App binaries may be compiled but must not be launched. App-only model regression runners may run with explicit synthetic config, disabled appearance/UserDefaults initialization and no NSApplication event loop/windows. Compile standalone runners with `swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$OUT/module-cache"`, linking only approved local Core/app model sources; report exact invocation.

### Test/data safety

- No GUI launch, real `--check`/`--snapshot`, mounts, real config, user inbox/archive/dump/Downloads/Trash, live photo scans, privileged commands or unfiltered legacy suite. Existing Finalize tests call real Trash; never run them by accident.
- Dedicated synthetic runs only. All inbox/archive/dump/card paths must live under OUT in UUID-named test roots; validate confinement before destructive tests and remove only your own synthetic roots with defer. Do not assume HOME or PC_FIXTURES isolates app config. Explicit config injection is required.
- No reject decisions/Trash in any new tests. Synthetic keep/undecided originals and generated JPEGs cover this wave. Fixture absence is a failure, not a skip; prefer generated fixtures. Assert marker pixels/bytes and identities, not only non-nil/dimensions.
- Preserve runnable focused checks in the assigned unique test/script paths. Controlled decoder barriers/reversed completion must have a bounded timeout to fail rather than hang. CHECK/assert collectors must not race.
- Existing `PhotoCullTests --finalize-safety-only` is an approved 58-check synthetic no-Trash regression. Run only that filter or another reviewed explicit filter; never invoke the executable with no arguments.

### Outputs/reporting

Report in OUT/report.md: supplied agent name and pane, branch/commit, files changed, exact build/check commands, check count/skips, source-proven changes versus measured timings, residual risks and any integration dependencies. Do not claim end-to-end/UI latency from kernel timings or notification counts. Prepare report before sending ONE completion/blocker notification to the parent pane supplied in the assignment. Do not poll or answer other agents' UIs.

Parent tracker: `2026-10-03_luna-performance-fixes_TODO.md`.
