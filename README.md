# ChordPlane

A guitar-first chord and lyric songbook for iOS and Android. Songs are stored in
[ChordPro](https://www.chordpro.org/) and live on the device; cloud sync and
Clerk accounts arrive in a later phase.

## What works today (Phase 1, local-only)

- **Library** — all songs or favorites, sorted by title, with an artist index
  and per-artist pages.
- **Song viewer** — chords above lyrics, transpose from −11 to +11 semitones
  with a reset, text zoom (buttons and pinch), autoscroll with an adjustable
  speed slider, and the screen kept awake while it runs.
- **Chord diagrams** — tap any chord (in the song or in the chord chips) to see
  its voicings, or open the all-chords sheet for the whole song. Guitar and
  ukulele, switchable in Settings.
- **Editor** — title, artist, key, capo, tempo, YouTube link, tags, and a live
  ChordPro preview, with a chord insertion toolbar.
- **Setlists** — create, rename, add songs in bulk, drag to reorder, remove, and
  copy the running order to the clipboard.
- **Sharing** — share a song or setlist as a `.cpl` file, a link, or a QR code.
  Self-contained: chords and lyrics travel in the link, so no server is needed.
  Import from a pasted link/code, the clipboard, or a `.cpl` file; songs already
  in the library are reused instead of duplicated.
- **Settings** — light/dark/system theme, instrument, sharp/flat spelling, text
  size, and a one-tap demo pack of public-domain songs.
- **Search** — matches titles, artists, lyrics, and tags.

Everything is stored with Drift/SQLite. `sync_outbox`, `version`, and
`sync_state` columns are already in the schema so cloud sync can be added
without a rewrite.

## Sharing format

`.cpl` files are pretty-printed JSON with a `format` marker
(`chordplane.cpl/1`). Links and QR codes carry the same JSON, gzipped and
base64url-encoded: `https://chordplane.app/c/<code>`. The app registers the
`chordplane://c/<code>` scheme, so cold-start links open the import screen
directly and pre-fill the code. HTTPS links start opening the app once
`chordplane.app` serves an `assetlinks.json` (Android) and an
`apple-app-site-association` file (iOS); until then they can be pasted into
Import.

## Running

```sh
flutter pub get
dart run build_runner build        # regenerate Drift code after schema edits
flutter run                        # pick a device or emulator
flutter test                       # 27 unit + widget tests
flutter analyze
```

Minimums: Android API 24, iOS 15 (set by `chord_diagrams`).

## Project layout

```
lib/
  app/            app root, router (go_router shell), theme
  core/
    auth/         local-only AuthGateway seam for Clerk later
    chords/       ChordDocument: parse + transpose + chord extraction
    db/           Drift tables and database
    demo/         public-domain demo songs
    settings/     persisted settings notifier
    utils/        slugify
  features/
    library/      library screen
    search/       search screen
    setlists/     setlist repository, list and detail screens
    settings/     settings screen
    sharing/      .cpl codec, share/import services, share sheet, import screen
    songs/        repositories, providers, viewer, editor, artists
  shared/         reusable song tile and empty states
```

## Notes

- The native diagram renderer needs `await ChordDiagrams.ensureInitialized()`
  before the first diagram is drawn; `main()` handles that.
- Chord spelling follows the Settings preference, falling back to the song key.
- iOS builds additionally require CocoaPods (`brew install cocoapods`).
