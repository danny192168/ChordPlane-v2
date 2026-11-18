# ChordPlane

A guitar-first chord and lyric songbook for iOS and Android. Songs are stored in
[ChordPro](https://www.chordpro.org/) and live on the device; the cloud is a
sync/mailbox layer (Supabase), never the source of truth.

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
- **Cloud links (opt-in)** — with Supabase configured, sharing also creates a
  short server link (`https://chordplane.citcs.site/s/<token>`): no size limit,
  a clean QR code, and viewable/importable without the app. Creating a link
  requires signing in (email + password); viewing never does. Shares created
  offline are queued and uploaded when connectivity returns.
- **Settings** — light/dark/system theme, instrument, sharp/flat spelling, text
  size, and a one-tap demo pack of public-domain songs.
- **Search** — matches titles, artists, lyrics, and tags.

Everything is stored with Drift/SQLite. `sync_outbox`, `version`, and
`sync_state` columns are already in the schema so cloud sync can be added
without a rewrite.

## Sharing format

`.cpl` files are pretty-printed JSON with a `format` marker
(`chordplane.cpl/1`). Inline links and QR codes carry the same JSON, gzipped and
base64url-encoded: `https://chordplane.app/c/<code>`. Server-backed links carry
only a token: `https://chordplane.citcs.site/s/<token>`. The app registers the
`chordplane://` scheme, so cold-start links open the import screen directly
and pre-fill the code. HTTPS links start opening the app once the link host
serves an `assetlinks.json` (Android) and an `apple-app-site-association`
file (iOS); until then they can be pasted into Import.

## Cloud setup (optional)

The app is fully functional without any backend. To enable cloud share links:

1. Create a Supabase project and run `supabase/migrations/0001_shared_bundles.sql`
   in its SQL editor.
2. Build/run with the project credentials:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Auth: email + password sign-in is enabled by default; magic-link and social
providers can be added in the Supabase dashboard later.

## Running

```sh
flutter pub get
dart run build_runner build        # regenerate Drift code after schema edits
flutter run                        # pick a device or emulator
flutter test                       # 27 unit + widget tests
flutter analyze
```

Minimums: Android API 24, iOS 15 (set by `chord_diagrams`).

## Android releases and the download page

The download page lives at <https://chordplane.citcs.site/download>. It is a
static HTML/CSS page in `web/download/`, which Flutter copies into
`build/web/download/`; the existing web-viewer deploy publishes it without any
extra steps. The page and the app both point at one stable asset name:

```
https://github.com/danny192168/ChordPlane-v2/releases/latest/download/chordplane-latest.apk
```

To publish a build:

1. Bump `version:` in `pubspec.yaml` if you also build locally (the tag wins
   for CI builds).
2. Tag and push:

```sh
git tag v1.2.0
git push origin v1.2.0
```

The `Release Android APK` workflow builds a signed release APK, uploads
`chordplane-latest.apk` and `chordplane-latest.apk.sha256`, and marks the release
as latest — which moves both the `/download` button and the in-viewer
“Get the app” link. `workflow_dispatch` accepts a tag name for re-running a
release without re-pushing the tag.

Signing secrets (`Settings → Secrets and variables → Actions`):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i keys/chordplane-release.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Optional repository variables `SUPABASE_URL` and `SUPABASE_ANON_KEY` override
the compiled-in cloud credentials; the workflow otherwise falls back to the
same public project the web viewer uses. Without them the APK still installs
and works locally, but cloud share links are disabled.

iOS has no public build yet; the page shows it as “coming soon”.

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
