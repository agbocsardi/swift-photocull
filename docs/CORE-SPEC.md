# PhotoCull Swift — Core Spec (port of the Go app)

Reference implementation: `/Users/agbocsardi/Documents/1-projects/photocull/` (Go).
The Swift core must be **behaviourally identical** and **data-compatible**.

Build/test loop (no Xcode, CommandLineTools only — XCTest is NOT available):

    cd /Users/agbocsardi/Documents/1-projects/swift-photocull
    swift build
    swift run PhotoCullTests      # exit 0 = pass

## 1. Config (`Config.swift`)

Path: `~/.config/photocull/config.toml`. Created with defaults on first run.

    [paths]
      inbox = "~/Pictures/PhotoCull/inbox"
      archive = "~/Pictures/PhotoCull/archive"
      dump = "~/Downloads"

    [files]
      raw_extensions = ["RAF", "RW2"]
      jpg_extensions = ["JPG", "JPEG"]

- Missing file → write defaults, then continue with defaults. Never fatal.
- Parse failure → also fall back to defaults (do not crash).
- `~/` expanded for all three paths.
- `toTOML()` must produce the same key names/shape Go writes (2-space indent under
  each section header, `key = "value"`, `key = ["A", "B"]`).
- `TOMLParser.parse` handles: `#` comments, `[section]` headers, `key = "str"`,
  `key = ["a", "b"]`, blank lines, optional trailing comments, whitespace.
  Keys outside any section go under `""`.

## 2. Session (`Session.swift`)

File: `<inbox>/{date}/.photocull.json`.

    {"version":1,"decisions":{"DSCF1234":"keep","P1000567":"reject"},"last_index":12}

- Decision values: `keep` | `reject` | `undecided`. Absence == undecided.
- Stem keys are **UPPERCASED**.
- `save` writes sorted keys, 2-space indent, and includes `crops` only when non-empty.
- `load` on a missing file → `Session.fresh()` (no throw). Corrupt JSON → fresh session
  is acceptable, but prefer throwing only on I/O errors; a corrupt file must not crash.
- `folderStatus`: no stems → `.empty`; no stem present in `decisions` → `.unstarted`;
  every stem present → `.complete`; else `.inProgress`.
- `CropRect.isFullFrame` tolerance 0.005 per edge. `clamped(minSize:)` clamps to 0...1
  and ensures `w >= minSize`, `h >= minSize` while keeping the rect inside the frame.

## 3. File pairs (`FilePair.swift`)

- Scan directory entries (skip subdirectories and dotfiles).
- Key = uppercased filename stem. Extension matched case-insensitively against the
  uppercased `jpgExts` / `rawExts` sets.
- JPG+RAW → pair; JPG only → pair with `raw == nil`; RAW only → `orphanRAWs`.
- Pairs sorted ascending by stem (plain lexicographic, same as Go's byte compare).
- Multiple JPGs sharing a stem: last one wins (Go behaviour).

## 4. Library (`Library.swift`)

- `loadSessions`: list immediate subdirectories of `cfg.paths.inbox`; skip unreadable
  ones; sort **newest date first** (descending string compare). Missing inbox → `[]`.
- `SessionRow.cropped` = number of stems with a crop in that folder's session.
- `Library.pairs(cfg:date:)` = `FilePairs.pairs` on the inbox folder.

## 5. EXIF (`Exif.swift`) — use ImageIO, not third-party code

Use `CGImageSourceCreateWithURL` + `CGImageSourceCopyPropertiesAtIndex`.
- `camera` = `"{Make} {Model}"` (single space; if only one is present, use it alone).
- `lens` = `kCGImagePropertyExifAuxDictionary` → LensModel, else EXIF LensModel.
- `iso` = EXIF ISOSpeedRatings first element, as decimal string.
- `shutter` = ExposureTime: `1/250s` when numerator is 1, else `n/ds`.
- `aperture` = FNumber formatted `f/%.1f`.
- `size` = `"{PixelWidth}×{PixelHeight}"` using the **U+00D7 multiplication sign**.
  When unavailable, `String(format: "%.1f MB", bytes/1e6)`.
- `dateTimeOriginal` = EXIF DateTimeOriginal, formatted `yyyy-MM-dd HH:mm:ss`.
- `orientation` = `kCGImagePropertyOrientation`, default 1.
- RAW files: ImageIO often can't read RAF/RW2 metadata; return an info struct with
  only `fileSizeBytes` set, and do not throw.
- `captureDate` returns `yyyy-MM-dd` from DateTimeOriginal, else the file's
  modification date, else `"undated"`.

## 6. Ingest (`Ingest.swift`)

- `detectSDCards`: directories under `/Volumes/` that contain a `DCIM` subdirectory,
  returned as the `DCIM` URL, sorted by path. Sorted case-insensitively.
- `run`: `source == nil` → auto-detect; none found → throw `.noSourceFound`.
- Recursively collect files whose uppercase extension is in jpg ∪ raw, sorted by path.
- For each: date folder = `captureDate`; `mkdir -p inbox/{date}`; collision-safe name
  (below); skip when destination exists with the same byte size; else copy the bytes.
- `safeDestName`: `seen[UPPER_STEM] += 1`; count 1 → original basename;
  else `"{stem}_{count}{ext}"` preserving the original case of stem and ext.
- `folders` in the result = sorted unique date folders written to.
- `onProgress` reports `total` once, then `current`/`copied` per file, then
  `running=false, done=true`. Errors go into `progress.error` **and** are thrown.
- Copying must preserve file modification dates (`FileManager.copyItem` does).

## 7. Finalize (`Finalize.swift`)

`summary(cfg:date:)`: counts by decision over the folder's pairs.

`run(cfg:date:dump:cropMode:dumpOverride:)`:
1. Resolve dump folder: `dumpOverride` if given, else `cfg.paths.dump/{date}`.
   Only created when `dump == true`.
2. For each pair, decision `reject` → trash `jpg` and `raw` (RAW first is fine).
3. Otherwise (keep **or** undecided) → archive `jpg` and `raw` into
   `cfg.paths.archive/{date}/`, and when `dump == true` write the JPG into the dump
   folder. With `.original` copy bytes; with `.applyCrop` and a non-full-frame crop,
   write a re-encoded cropped JPEG via `ImagePipeline.export` and count it in `cropped`.
4. Orphan RAWs → archive.
5. Delete `.photocull.json`, then delete the inbox date folder.
6. Name collisions in archive/dump get a `_2`, `_3`… suffix.

`trash`: use `FileManager.trashItem(at:resultingItemURL:)`; fall back to moving into
`~/.Trash` with a `_<timestamp>` suffix on collision.

`runMulti`: single dump folder named by `dumpFolderName(dates:)` =
sorted first date for one date, else `"<first> to <last>"`.

## 8. Image pipeline (`ImagePipeline.swift`)

- `load`: `CGImageSourceCreateThumbnailAtIndex` with
  `kCGImageSourceCreateThumbnailFromImageAlways: true`,
  `kCGImageSourceThumbnailMaxPixelSize: maxPixel`,
  `kCGImageSourceCreateThumbnailWithTransform: true` (this applies EXIF orientation),
  `kCGImageSourceShouldCacheImmediately: true`.
- `thumbnail`: same but allow `kCGImageSourceCreateThumbnailFromImageIfAbsent`.
- `orientedPixelSize`: EXIF PixelWidth/PixelHeight swapped when orientation is 5...8.
- `crop`: rect is normalized in oriented space with **origin top-left**; convert to
  CGImage pixel space (which is top-left origin for CGImage cropping with
  `cropping(to:)`) and guard against zero/out-of-range sizes. Full-frame → return input.
- `applyOrientation`: the 8 EXIF cases (1 none, 2 flip H, 3 rotate 180, 4 flip V,
  5 transpose, 6 rotate 90 CW, 7 transverse, 8 rotate 90 CCW).
- `writeJPEG`: `CGImageDestinationCreateWithURL` with `kUTTypeJPEG`/`UTType.jpeg.identifier`.
- `export`: nil or full-frame crop → byte copy (`FileManager.copyItem`); else decode at
  full resolution, crop, write JPEG at the given quality.
- `ImageCache`: LRU, capacity-bounded, `NSLock`-protected.

## Test expectations

Every suite must assert real behaviour against temp directories, and must exercise the
bundled fixture JPEGs when present via `fixtureURL("20240503-DSCF2771.jpeg")` (skip
gracefully when nil). No network, no writes outside temp dirs.
