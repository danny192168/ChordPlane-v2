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

Auth: email + password sign-in is enabled by default. Native Google Sign-In is
also supported, but stays hidden until a Google client ID is compiled in (see
[Accounts and Google sign-in](#accounts-and-google-sign-in)).

## Accounts and Google sign-in

Sign-in is only needed to create cloud share links; the library works without
an account. The app supports:

- **Email + password** — sign up, confirmation email, resend confirmation.
- **Google** — the native Android/iOS account picker, exchanged for a Supabase
  session with `signInWithIdToken`.
- **Password reset** — a `chordplane://reset-password` link opens the
  “choose a new password” screen.

On the web viewer the Google button is hidden; email sign-in is native-app only.

### Google Cloud Console

1. Open [Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients).
   If the project has never had a consent screen, fill in **Branding**
   (`/auth/branding`) and **Audience** (`/auth/audience`, External) first, and
   request only `openid`, `.../auth/userinfo.email` and
   `.../auth/userinfo.profile` under **Data Access**. Then create four clients:

   | Type | Configuration |
   | --- | --- |
   | Web application | Authorized redirect URI: `https://eweppodjncodtsiljvak.supabase.co/auth/v1/callback` |
   | Android | Package name `app.chordplane.chord_plane` plus the release SHA-1 below |
   | Android | Same package name plus the debug SHA-1 below |
   | iOS | Bundle ID `app.chordplane.chordPlane` |

   An OAuth client holds a single SHA-1, so release and debug builds need
   separate Android clients. Only the Web client has a secret; the Android and
   iOS clients are identified by ID alone.

2. Android SHA-1 fingerprints for this repository:

   ```text
   release: 65:6E:6B:B7:8D:E6:30:AC:79:E5:1A:36:E3:BB:E4:D5:08:60:3E:C6
   debug:   64:ED:11:A7:B7:73:FB:3E:8B:9D:B3:A6:DB:56:8F:C0:77:B6:A4:AD
   ```

   Regenerate them after replacing the keystore:

   ```sh
   keytool -list -v -keystore keys/chordplane-release.keystore | grep SHA1
   keytool -list -v -keystore ~/.android/debug.keystore -storepass android | grep SHA1
   ```

   A build distributed through Google Play is re-signed by Play, so its App
   Signing SHA-1 must be added as a second Android OAuth client too.

3. The **Web** client ID and secret go into Supabase. The **iOS** client ID is
   public and is used directly by the app. No `google-services.json` is needed.

### Supabase Dashboard

1. **Authentication → Providers → Google**: enable it and paste the Web client
   ID and secret.
2. Add the **Android** and **iOS** client IDs to **Authorized Client IDs**,
   comma-separated with the Web client first. Supabase verifies the ID token
   audience, which is the Web client on Android and the iOS client on iOS.
3. Turn on **Skip nonce check** in the same panel. The native flow exchanges an
   ID token without a nonce, and iOS sign-in fails without this even when every
   client ID is correct.
4. **Authentication → URL Configuration**:
   - Site URL: `https://chordplane.citcs.site`
   - Redirect URLs: `chordplane://**` and
     `https://chordplane.citcs.site/auth/confirm`
5. For production sign-ups configure **custom SMTP**; the built-in email sender
   is rate-limited, only delivers to project team members, and is not meant for
   real users.

`web/auth/confirm/index.html` is the static landing page for confirmation
links. It forwards the `code` (or implicit-flow tokens) to
`chordplane://auth-callback` and shows an “Open ChordPlane” fallback when the
email is opened on a desktop.

### Building with Google

Pass the public client IDs at build time. The Android release workflow reads
them from the repository variables `GOOGLE_WEB_CLIENT_ID` and
`GOOGLE_IOS_CLIENT_ID`:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_WEB_CLIENT_ID=WEB_ID.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=IOS_ID.apps.googleusercontent.com
```

Without `GOOGLE_WEB_CLIENT_ID` the Google button is hidden and email sign-in
continues to work.

For iOS, `ios/Runner/Info.plist` carries the client ID twice — as `GIDClientID`
and as the reversed-client-ID URL scheme that brings the account picker back
into the app:

```xml
<key>GIDClientID</key>
<string>IOS_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.IOS_ID</string>
    </array>
  </dict>
</array>
```

Keep the existing `chordplane` URL scheme entry alongside this one. If the iOS
client is ever recreated, change both occurrences in the plist and the
`GOOGLE_IOS_CLIENT_ID` variable together — a stale one produces a token whose
audience Supabase will not accept.

### Before the App Store

Apps that offer Google sign-in must also offer **Sign in with Apple** under
App Store guideline 4.8. That provider is intentionally not part of this
change: it needs an Apple Developer Services ID/key, the Supabase Apple
provider, and an `Xcode` capability. Add it before submitting the iOS build.

## Running

```sh
flutter pub get
dart run build_runner build        # regenerate Drift code after schema edits
flutter run                        # pick a device or emulator
flutter test                       # unit + widget tests
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
