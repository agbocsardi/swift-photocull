# Disposable GUI / Finalize fixture (preparation only)

**STOP: the reviewed app has no supported independent startup config. No safe
launch command is available. Do not launch it, even with HOME/PC_FIXTURES set.**
This checklist is a deferred manual test, not authorization to launch or Trash.
The parent must independently review the fixture and isolation changes, then
obtain explicit user authorization for GUI and native Trash actions.

## Prepare / validate (no PhotoCull launch)

From the checkout, run `scripts/prepare-manual-finalize-fixture.sh` with no arguments.
It always allocates a new canonical `/private/tmp/photocull-manual-fixture-*` root,
mode 0700. It uses only installed Swift/macOS APIs, snapshots the actual relevant
production sources, and compiles a small generator/validator directly with
`swiftc`. All build, module, Clang, temporary, config/security/cache directories,
logs, inputs, proposed TOML, pure image-export probe, and manifest stay in that
root. No SwiftPM build, dependency install, shared `.build`, or `dist` edit.

Let ROOT be the exact printed canonical root. Non-destructive validation:

```sh
"$ROOT/tool/fixture" validate "$ROOT"
# ONLY after a separately authorized successful manual Finalize:
"$ROOT/tool/fixture" validate-finalized "$ROOT"
```

Validation never launches the app, invokes Finalize.run, calls card detection,
reads the real saved config, writes config/sidecars, or inspects system Trash.
It rejects noncanonical roots, all descendant symlinks/special files and wrong
managed file sets, checks hashes and actual ImageIO decode, and uses actual
production `PCConfig.load(from:)`, Library, FilePairs, ExifReader, ImagePipeline
and read-only `Finalize.summary`. The pure generator crop probe exercises the
real export pipeline on generated #03, with a square crop and +2° tilt.
Initial validation deliberately fails once GUI changes have created a sidecar.
No automated cleanup is supplied; keep the external root until review is done.

## Layout / intentions

- `config/config.toml`: **proposed only, not selectable by current GUI startup**.
  Absolute inbox/archive/dump paths are ROOT/inbox, ROOT/archive, ROOT/export.
  Standard JPG/JPEG and RAF/RW2 extension lists; no RAW files are generated.
- `inbox/2024-05-03/`: exactly six valid 960×640 JPEGs, capture date embedded in
  EXIF, numbered colored grids, horizontal reference line, asymmetric corner
  features, and filenames matching the intentions below.
- `archive/`, `export/`: separate, empty roots; no collision suffixes expected.
- Session `notes.txt` and `unrelated-subfolder/marker.txt`: unrelated preserved
  entries. No `.photocull.json` seeded; all six start undecided.
- `checks/crop-probe.JPG`: 640×640 generated output, NOT a library input.
- `manifest.json`: exact input SHA256/bytes/dimensions, desired decisions,
  paths, expected counts and file outcomes. Tool/source snapshots and provenance
  are under `tool/`; the root survives worktree removal.
- No mock card is needed: config has no card-source setting and this test starts
  directly from a generated inbox. **Do not open Ingest** (it scans real mounts).

| JPEG | Manual action | Archive | Export with crop applied | Native Trash |
|---|---|---|---|---|
| 01_RED_KEEP.JPG | Keep; no edits | original 960×640/hash | identical 960×640/hash | no |
| 02_GREEN_KEEP.JPG | Keep; no edits | original 960×640/hash | identical 960×640/hash | no |
| 03_BLUE_EDIT_KEEP.JPG | Keep; 1:1 preset, +2° tilt | original 960×640/hash | edited 640×640/new hash | no |
| 04_ORANGE_REJECT.JPG | Reject | absent | absent | original JPEG |
| 05_PURPLE_REJECT.JPG | Reject | absent | absent | original JPEG |
| 06_CYAN_UNDECIDED.JPG | Leave undecided | original 960×640/hash | identical 960×640/hash | no |

Successful destinations: ROOT/archive/2024-05-03 and ROOT/export/2024-05-03.
Undecided is **treated as keep**, not left in the inbox. Counts: 3 keep, 2 reject,
1 undecided, 6 total, 0 RAW; Finalize: 4 archived, 2 trashed, 4 exported, 1 edited.
Native macOS Trash is intentionally NOT redirected into ROOT by config. The OS
chooses its real destination (possibly with collision renaming); Trash may fail.
No fixture preparation or validation tests that API or empties/removes Trash.

## Deferred manual checklist — BLOCKED until independent isolation review

- [ ] Parent reviews source/bundle provenance, config containment and read-only
  validation; approves an independent-config mechanism before any launch.
- [ ] User separately authorizes app launch/GUI and then actual macOS Trash.
  Config isolation does NOT isolate native Trash. No real volumes/cards/photos.
- [ ] Before launch, all managed roots match the printed canonical ROOT, no
  symlinks, archive/export empty. Safe launch command comes from parent review,
  not this checklist. No real config replacement/backup-and-restore workaround.
- [ ] At initial UI, only 2024-05-03 appears: six undecided photos, no RAW badges.
  Inspect six distinct numbers/colors; use filmstrip and left/right arrows to
  navigate. `j/k` navigate photos only when photo/filmstrip focus, not sidebar.
- [ ] On #03 try a crop/tilt draft then Esc; confirm draft is not saved. Reenter
  with `c`/Crop, select 1:1 (do not resize/move it), use period eight times to set
  +2° tilt from zero, then Enter/Apply. Check square preview/reference-line tilt.
  If testing Undo/Redo, ensure final saved state is again 1:1/+2°. No rotation.
- [ ] Set Keep on #01/#02/#03, Reject on #04/#05, leave #06 undecided. `z` and `x`
  mark and auto-advance; pressing the same decision again clears it. Recheck
  filenames before marking; navigation alone persists last_index in sidecar.
- [ ] Use Cull → Finalize Current Session (⌘F), not Ingest or repair. Wait for
  summary: Keep 3 / Reject 2 / Undecided 1 / Total 6; undecided-as-keep warning;
  copies path ROOT/export. Choose **Keep JPGs with the crop applied**. First
  Cancel; verify no moves/Trash and archived/export folders remain empty.
- [ ] Reopen summary and recheck it. Only with separate actual Trash permission,
  confirm Finalize once. Do not expect undo to restore originals after Finalize;
  app clears affected undo/session references. Do not quit while bulk work runs.
- [ ] Inspect four archives and four exports; originals' hashes match manifest,
  #03 export is 640×640 edited; #01/#02/#06 exports are byte-identical. Run
  `validate-finalized` for these root-local outcomes (it never inspects Trash).
- [ ] Session date folder remains with sidecar/notes/nested marker unchanged;
  an empty-photo session row can remain. Do not expect recursive deletion.
  Success toast reports 4 archived / 2 trashed and retained folder path.
- [ ] User manually inspects ONLY the two generated reject items in macOS Trash;
  compare original bytes/hashes if authorized. Do not empty Trash, automatically
  restore/remove items, or inspect unrelated Trash items. Absence from inbox is
  not proof of recoverability. This step is unperformed by the fixture agent.
- [ ] On any failure/recovery record/claim folder, STOP. Preserve ROOT and partial
  archive/export/claims; report paths. No blind retry or automatic cleanup.

## Source isolation evidence / smallest proposed changes (not implemented)

Evidence at base `1f638de` (snapshotted under ROOT/tool/sources):

1. `PhotoCullApp.swift`: GUI owns `AppState()` with no config argument; CLI checks
   only --repair-pairs/--apply and --check before GUI. `AppState.init` defaults to
   `PCConfig.load()`, immediately scans the configured inbox and opens a session.
2. `Config.swift`: configPath is NSHomeDirectory()/.config/photocull/config.toml;
   load() always uses it, writes defaults if missing/unreadable and expands ~.
   Defaults include the user's Pictures/PhotoCull and Downloads. `load(from:)`
   exists for code/tests but is not exposed by the app. HOME/PC_FIXTURES is not a
   supported GUI isolation contract; PC_FIXTURES appears in the test harness only.
3. `HeadlessCheck.swift`: both CLI routes call PCConfig.load(); --check also scans
   /Volumes. Neither is a safe diagnostic command here. `Snapshot.swift` and
   ContentView's --crop affect display/output only, not config selection.
4. `Library.swift`, `AppState.swift`, `Session.swift`: library, metadata reads,
   navigation/decision/crop sidecar writes follow cfg.paths.inbox/date. Merely
   changing paths after startup is too late (startup has already read real data).
   ContentView's settings case presents HelpSheet, not an independent-config UI.
5. `Finalize.swift`: GUI confirm calls runMulti(dump:true); archive and dump are
   cfg.paths.archive/date and cfg.paths.dump/date. Nonrejects include undecided;
   originals archived unchanged, only exported copies receive edits. Rejects use
   FileManager.trashItem on exclusively claimed originals. No production Trash
   override from config/environment (`FinalizeSafety.swift` hooks are code-only).
   Empty-only rmdir preserves sidecars and unrelated entries; failures retain
   recovery records/claims, blocking silent retry.
6. `AppState.beginIngest` unconditionally calls detectSDCards before a source can
   be chosen; `Ingest.swift` enumerates /Volumes/*/DCIM. Supplying a mock directory
   later does not isolate the initial volume scan. This fixture excludes Ingest.
7. `AppState.swift` reads/writes UserDefaults.standard for appearance even on
   startup; config isolation alone does not isolate app preferences. PairRepair
   default audit logs use PCConfig.configPath (avoid repair), and Preview/Finder
   launch external apps (avoid them). Snapshot path is user-selected, not a
   sandbox boundary (avoid snapshots unless parent separately approves a path).

Smallest proposed production change for parent consideration: a documented,
strict startup `--config <absolute-file>` option resolved **before any AppState
or headless load**, feeding that exact explicit configuration through GUI/CLI
and config-relative audit logs. Explicit-config missing/malformed/incomplete
paths must fail closed, not fall back to defaults. For full preference isolation,
use an independent appearance store/domain with no standard-defaults access in
that mode (or disable persistence/standard reads for a disposable mode). No
Ingest change is needed for this restricted Finalize checklist because Ingest is
excluded; testing Ingest later requires bypassing auto-detection with an explicit
source before any /Volumes access. These changes require separate authorization
and review; this branch adds no production code or unsafe launch instructions.

Limits: this is generated JPG-only/same-volume input, not camera RAW/embedded-
preview fidelity, physical-card/cross-volume/crash testing, GUI validation or
native Trash validation. Compiling the production subset proves fixture format
and read-only paths, not GUI launch isolation or bundled-source identity.
