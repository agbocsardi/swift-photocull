# Disposable GUI / Finalize fixture

**Preparation is NOT launch permission. Parent independently reviews the source,
checks and candidate before any user-authorized GUI/native Trash test. Never
launch the ordinary dist app for this workflow, or replace its saved config.**

## Preparation and checks (no app launch)

- `scripts/prepare-manual-finalize-fixture.sh`: generate only six JPEGs, proposed
  TOML, manifest, pure image-export probe, checker and this checklist in a fresh
  canonical `/private/tmp/photocull-manual-fixture-*` root. No app bundle/release build.
- `scripts/check-fixture-startup.sh`: full isolated release compile, focused native
  startup/ownership/I/O guard checks with effective negative controls, existing
  focused operation/navigation regressions, and an ad-hoc signed **separate**
  `PhotoCullFixture.app`. Build/check products live in fresh canonical
  `/private/tmp/photocull-manual-launch-*` roots. It generates another fresh launch
  fixture as the eventual writable GUI target, never the read-only shared inputs.
  Candidate/fixture paths, unique bundle ID, hash, signature log and proposed
  launch command are recorded in its output. The script never executes PhotoCull.

No installs, dependencies, framework additions, shared `.build`, dist replacement,
ordinary diagnostics, cards, native Trash or GUI actions. Native macOS APIs only.
Every compiler/SwiftPM/Clang cache/config/security/temp output is isolated. Existing
shared preparation roots are hashed read-only before/after and never modified.
Do not use `scripts/build-app.sh` here (it writes shared build/dist outputs).

Given ROOT = printed **data fixture** root, read-only validation:

```sh
"$ROOT/tool/fixture" validate "$ROOT"
# ONLY after a separately authorized successful manual Finalize:
"$ROOT/tool/fixture" validate-finalized "$ROOT"
```

Validation rejects noncanonical roots/symlinks/special files, verifies exact config
and managed file sets, hashes, native JPEG decode/thumbnail/dates and actual
production strict fixture Config/Library/FilePairs/read-only Finalize.summary.
The generator exercises pure ImagePipeline.export on generated #03 only; it
never calls Finalize.run/Trash. Initial validation fails once GUI creates a sidecar.
No automated cleanup, Trash emptying or removal/restore instructions are provided.

## Supported fixture startup — only after parent review and GUI permission

The **dedicated** startup option is exactly:

`PhotoCullFixture.app/Contents/MacOS/PhotoCull --fixture-config <absolute-canonical-config>`

Use the EXACT absolute candidate/config paths from `proposed-launch.txt`, after
parent review. Do not execute this documentation placeholder or an ordinary app.
Direct executable launch avoids Finder/LaunchServices-added command-line flags.
The option is accepted only when Bundle.main identifies a separately prepared
`local.photocull.fixture.<UUID>` bundle, distinct from `local.photocull.swift`.
A fixture-identified bundle without the option, the ordinary app with the option,
unbundled use, invalid identity, missing/duplicate option, or ANY additional
flags (including --check/--repair-pairs/--apply/--snapshot/--crop/--appearance)
exits 2 before default config, headless dispatch, AppState or SwiftUI startup.
Double-clicking this fixture app fails closed; no HOME/PC_FIXTURES override.

Strict `PCConfig.loadFixture(from:)` never uses the ordinary permissive loader or
writes defaults. It requires:

- Existing absolute canonical ROOT/config/config.toml; ROOT directly under
  `/private/tmp`, named `photocull-manual-fixture-*` or `photocull-manual-launch-*`.
- Owned readable regular non-symlink, non-hardlinked config, owned real root/config
  directories; root must be private (no group/other permissions). Native pinned
  read, UTF-8, size ≤16 KiB, replacement/change refusal.
- **Exactly generated TOML serialization**: all three explicit absolute paths and
  extension lists; paths ROOT/inbox, ROOT/archive, ROOT/export; arrays RAF/RW2 and
  JPG/JPEG in generated order. Comments, duplicates, unknown keys, alternative
  whitespace/formatting, incomplete/malformed config all fail closed.
- All three existing separate owned real data directories; every descendant is
  owned, readable regular (not hardlinked) or a real directory. No symlink,
  special-file or path escape. File permissions are not bypassed.

This generated-only TOML ceiling is intentional: no new TOML/config framework.
The fixture is a controlled generated tree, **not an OS filesystem sandbox**.
Startup validation is not continuous confinement against an owner/malicious
process replacing directories or planting links later. Keep the roots private,
use only the generated files, and do not externally mutate them during GUI work.

## Preference / I/O isolation boundaries

Fixture AppState skips its explicit UserDefaults.standard appearance read/write;
appearance is transient. SwiftUI/AppKit automatic window/state preferences use
the fresh bundle identifier. **OS-created preferences/saved state for that unique
identifier may live outside ROOT** (e.g. user Library paths). They are disposable
application-domain state, not the ordinary PhotoCull preference domain. We never
read, edit/delete or back up ordinary preferences, and never use global preference
settings or HOME overrides. This is domain isolation, not proof that macOS internals
never read system-wide UI settings. GUI/framework persistence has not been live-tested.

Shared AppState entry methods refuse Ingest/startIngest, pairing check/repair/apply,
Preview and Finder BEFORE any flush, volume discovery or external-app/audit I/O.
The ordinary menu-bar extra (with a direct Finder action) is not inserted in fixture
mode. Snapshot callbacks are also suppressed; mixed snapshot/diagnostic CLI flags
are rejected before startup. Normal startup/flags/preferences remain unchanged.
Use only local navigation, decisions, crop/tilt, confirmation/cancel and quit.

Native macOS Trash is **not** redirected or mocked by production fixture mode.
It remains a real OS side effect requiring separate explicit authorization.
Preparation/checks never call it. A unique bundle identity does not sandbox Trash.

## Layout / intended manual outcomes

ROOT/config/config.toml routes inbox/archive/dump to ROOT/inbox, ROOT/archive and
ROOT/export. Six genuine 960×640 JPEGs in inbox/2024-05-03 have stable EXIF capture
dates, colored numbered grids/reference lines/asymmetric corners. No RAW/card
inputs or seeded `.photocull.json`; all six initially undecided. Archive/export
start empty. Unrelated notes.txt and unrelated-subfolder/marker.txt must survive.
checks/crop-probe.JPG is a 640×640 generated output, NOT a seventh inbox input.
manifest.json supplies full original SHA256/bytes/dimensions and file intentions;
launch_cleared stays false even when a candidate is prepared. External fixture
roots survive worktree cleanup; preserve them for review.

| JPEG | Manual action | Archive | Crop-applied export | Native Trash |
|---|---|---|---|---|
| 01_RED_KEEP.JPG | Keep; no edits | original 960×640/hash | identical 960×640/hash | no |
| 02_GREEN_KEEP.JPG | Keep; no edits | original 960×640/hash | identical 960×640/hash | no |
| 03_BLUE_EDIT_KEEP.JPG | Keep; 1:1 preset, +2° tilt | original 960×640/hash | edited 640×640/new hash | no |
| 04_ORANGE_REJECT.JPG | Reject | absent | absent | original JPEG |
| 05_PURPLE_REJECT.JPG | Reject | absent | absent | original JPEG |
| 06_CYAN_UNDECIDED.JPG | Leave undecided | original 960×640/hash | identical 960×640/hash | no |

Successful destinations: ROOT/archive/2024-05-03 and ROOT/export/2024-05-03.
Undecided is treated as keep, not left in the inbox. Summary: 3 keep, 2 reject,
1 undecided, 6 total, 0 RAW. Finalize: 4 archived, 2 trashed, 4 exported, 1 edited.
OS chooses Trash location/name, potentially collision-renamed; native Trash can
fail. Root-local output validation never proves Trash presence or recoverability.

## Deferred manual checklist — not launch-cleared by preparation

- [ ] Parent reviews source/commit, native test logs, source/bundle provenance,
  unique disposable identifier, strict signature/hash and config containment;
  independently reruns checks. Candidate is never installed over dist/ordinary app.
- [ ] User separately authorizes that exact candidate GUI launch. Only then use
  proposed-launch.txt's absolute direct executable/config command. No extra flags,
  real config/library/photos/cards/mounts or modifications to shared input roots.
- [ ] Before launch, data fixture passes initial validation; archive/export empty,
  no sidecar/symlinks. No other process mutates the roots during the manual test.
- [ ] Only 2024-05-03 appears: six undecided numbered/color-distinct photos, no RAW.
  Filmstrip/left-right navigate photos; j/k navigate photos only with photo/filmstrip
  focus, not sidebar. Ingest/repair/Preview/Finder refuse with a fixture toast;
  do not use these excluded actions as part of normal manual acceptance.
- [ ] On #03 try a crop/tilt draft then Esc; confirm draft isn't saved. Reenter
  with c/Crop; select 1:1, do not move/resize; period eight times sets +2° from zero;
  Enter/Apply. Check square preview and tilted reference line. If Undo/Redo tested,
  final saved state remains 1:1/+2°, no rotation.
- [ ] Keep #01/#02/#03, Reject #04/#05, leave #06 undecided. z/x mark and auto-
  advance; pressing same decision again clears it. Check filename before marking.
- [ ] Cull → Finalize Current Session (⌘F); wait for Keep 3 / Reject 2 / Undecided 1 /
  Total 6 and undecided-as-keep warning. Copies path is ROOT/export; select Keep
  JPGs with the crop applied. First Cancel; no file moves/Trash, outputs still empty.
- [ ] Reopen/recheck summary. ONLY with separate explicit native Trash permission,
  confirm once. No automatic recovery/undo promise; don't quit during bulk work.
- [ ] Four archives/four exports match the table; run validate-finalized for
  root-local hashes/dimensions. Originals unchanged, #03 export square/edited.
- [ ] Date folder remains with sidecar/notes/nested marker. A zero-photo session
  row can remain. Success toast: 4 archived / 2 trashed and retained folder path.
- [ ] User manually inspects ONLY the two generated reject items in macOS Trash
  if separately authorized. Never empty Trash, auto-remove/restore, or inspect
  unrelated items. This step was not performed by the fixture agent/checks.
- [ ] Failure/recovery record/claims: STOP and preserve ROOT/partial outputs;
  report exact locations, no blind retry, automatic rollback or recursive cleanup.

Limitations: generated JPG-only/same-volume data, not camera RAW/embedded-preview
fidelity, physical cards/cross-volume/crash testing or live GUI/Trash validation.
Existing focused operation checks use generated synthetic RAW marker bytes and
instance-local synthetic Trash hooks; these are NOT fixture app inputs or a
production fake Trash option. Native tests never access ordinary config/preferences.
