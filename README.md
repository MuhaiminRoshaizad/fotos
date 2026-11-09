# fotos

A local-only gallery and file manager for one Android phone, built to replace
Google Photos. It also imports Google Takeout archives, so every photo and video
can leave Google with its original date.

Nothing leaves the phone: there is no account, no cloud and no internet
permission in release builds.

## What it does

- **Photos and Videos** — every item on the phone, newest first by date taken,
  grouped by year, month or day. Pinch between levels, scrub by date, long-press
  and drag to select. Share, add to an album (move or copy), favourite, delete
  to Android's trash with Undo.
- **Viewer** — swipe between items, down to close, up for details (date, file,
  camera, location). Pinch or double-tap to zoom. Videos: double-tap a side to
  skip 10 s, hold for 2× speed, scrub on a filmstrip, loop and mute.
- **Albums** — the phone's folders, with pins, chosen covers and per-album sort
  (date, name, length). New album, Favourites, and Recently deleted with restore.
- **Files** — every folder on the phone (needs All files access). PDFs open in a
  reader, text files as text, ZIPs extract with progress; anything else goes to
  Android's Open with. Rename, move, copy, share and delete.
- **Import from Google Takeout** — reads each ZIP part, copies media into
  `Pictures/Takeout/<year>` and `Movies/Takeout/<year>` with the date from
  Takeout's JSON, skips exact duplicates, sets possible duplicates aside for a
  side-by-side review, skips Locked Folder, and resumes after an interruption.

## Requirements

- Android 11 (API 30) or newer. Android only.
- Flutter 3.44.6 (pinned in `pubspec.yaml`).

## Run and install

```sh
flutter pub get
flutter run                       # debug, on a connected phone
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
```

Release builds are signed with the machine's debug key unless
`android/key.properties` points at an upload key. Builds from the same machine
install over each other; a build signed with a different key needs the old app
uninstalled first.

## Development

```sh
dart format lib test
flutter analyze
flutter test
```

CI runs the same checks and a debug build on every push to `main` and every
pull request (`.github/workflows/ci.yml`).

Layout: `lib/app` (router and shell), `lib/core` (theme, media library access,
shared widgets, the Android channel), `lib/features/<feature>` (albums, files,
library, takeout_import, viewer). Android-only work — trash listing, file
access, ZIP extraction, PDF pages, the Takeout importer — lives in
`android/app/src/main/kotlin/my/minned/fotos/`.
