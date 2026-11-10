# Stash

Save Instagram and TikTok posts into folders straight from the share sheet. Stash suggests a folder; one tap on **Save** files the post and returns you to the app you were in.

```
app/        Flutter app (Android + iOS)
  lib/share/            share sheet UI + logic (Android share activity)
  android/.../ShareActivity.kt   ACTION_SEND text/plain target
  ios/StashShare/       native Swift Share Extension sources
backend/    Node service: metadata, redirect resolution, AI folder suggestion
supabase/   schema for optional multi-device sync
```

## How it works

- **Android**: `ShareActivity` is a translucent activity that runs a second Dart entrypoint (`shareMain`), so the sheet draws over Instagram/TikTok and shares all logic with the main app.
- **iOS**: the Share Extension is native SwiftUI (fast to launch, well inside the extension memory limit). It reads and writes the same SQLite file as the Flutter app through the App Group container, so there is no hand-off step.
- **Suggestion order**: a folder you previously used or corrected for this author → keywords learned from your corrections → the LLM (existing folder, or a proposed new one) → last-used folder → Unsorted. If nothing answers within 1.5s the fallback is used and never swapped out from under your thumb.
- **AI description**: the AI writes a one-sentence description of each post from its caption and cover image. Cards show it (marked with a sparkle) in place of the raw caption, and search covers it.
- **Sorting by content**: when no existing folder matches a post's topic, the AI proposes a new folder and it is created on save. Posts saved before the AI could answer are sorted the next time the app is open and online, including into new folders.
- **Offline**: saving only needs the URL. Posts saved without a preview, or filed by fallback, are finished by a queue the next time the main app is open and online.
- **Duplicates**: a link that is already saved shows where it lives and turns Save into "Move to …".

## 1. Backend

```bash
cd backend
npm install
cp .env.example .env     # then fill in the keys below
npm start                # listens on :8787
```

| Endpoint | Purpose |
|---|---|
| `POST /v1/metadata` `{url}` | resolve short links, then TikTok oEmbed / Meta oEmbed, falling back to Open Graph tags |
| `POST /v1/resolve` `{url}` | redirect resolution only (hosts are allow-listed) |
| `POST /v1/suggest` | AI description of the post, plus a folder (existing or new) |

### Putting it online

A phone can only reach the backend if it runs somewhere public. The repo includes a Render blueprint (`render.yaml`) and a `backend/Dockerfile` for any other host.

With Render:

1. Push this folder to a GitHub repository.
2. At <https://render.com> choose **New → Blueprint** and pick the repository.
3. Fill in `ANTHROPIC_API_KEY` (and `META_APP_TOKEN`, `APP_KEY` if you use them) when asked.
4. When the deploy finishes, copy the service URL (`https://….onrender.com`).
5. In the app: **⋮ → Settings → Server**, paste the URL and tap **Save and test**.

The address is stored on the device and used by both the app and the share sheet, so the same APK works with any server. To bake it in instead, build with `--dart-define=STASH_BACKEND_URL=...`.

Render's free plan sleeps when idle and takes up to a minute to wake. The first share after a pause will fall back to the last-used folder; a paid instance (or any always-on host) avoids that.

### AI API key

Create a key at <https://platform.claude.com> and set `ANTHROPIC_API_KEY` in `backend/.env`. Without it `/v1/suggest` returns no suggestion and the app uses its local rules and fallbacks.

The model defaults to `claude-opus-5-5` at low effort. Set `SUGGEST_MODEL=claude-haiku-5-5` if you want more headroom under the 1.5s budget.

### Meta oEmbed token (Instagram)

1. At <https://developers.facebook.com> create an app and add the **oEmbed** product ("Meta oEmbed Read" feature; it needs App Review before it works for the public).
2. Use an app access token: `APP_ID|APP_SECRET` from *App settings → Basic* (or `APP_ID|CLIENT_TOKEN` from *Advanced*).
3. Set it as `META_APP_TOKEN` in `backend/.env`. It never leaves the backend.

Without the token, Instagram previews come from Open Graph tags only, which Instagram serves inconsistently to servers.

## 2. App

```bash
cd app
flutter pub get
flutter run --dart-define=STASH_BACKEND_URL=https://your-backend.example.com
```

Without `STASH_BACKEND_URL` debug builds use the dev machine (`10.0.2.2:8787` on the Android emulator, `127.0.0.1:8787` on the iOS simulator). On a real device use a URL the phone can reach. If you set `APP_KEY` on the backend, also pass `--dart-define=STASH_APP_KEY=...`.

Android needs nothing else: install, then share any post to **Stash**. To try it without Instagram:

```bash
adb shell am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "https://www.instagram.com/reel/XXXX/" -n com.example.stash/.ShareActivity
```

## 3. iOS: App Group and Share Extension

The extension's sources are in `app/ios/StashShare/`, but the Xcode target has to be created on a Mac (about five minutes):

1. Open `app/ios/Runner.xcworkspace`. Set your team and bundle id on **Runner**.
2. **Runner → Signing & Capabilities → + Capability → App Groups**, add `group.<your.bundle.id>`.
3. **File → New → Target → Share Extension**, name it `Share`, language Swift. Decline activating the scheme.
4. Delete the files Xcode generated for it (`ShareViewController.swift`, `MainInterface.storyboard`, `Info.plist`).
5. Drag the Swift files from `ios/StashShare/` into the project with target membership **Share** only.
6. In the **Share** target's Build Settings set *Info.plist File* to `StashShare/Info.plist`, *Code Signing Entitlements* to `StashShare/StashShare.entitlements`, and the iOS deployment target to the same value as Runner (15.0).
7. Add the same **App Groups** capability and group to the **Share** target.
8. **Runner → Build Phases**: drag *Embed Foundation Extensions* above *Thin Binary* (otherwise Xcode reports a build cycle).
9. Put your group id in the four places it appears: `Runner/Runner.entitlements`, `StashShare/StashShare.entitlements`, `appGroupId` in `StashShare/SharedStore.swift`, and `Config.appGroupId` in `lib/config.dart`.
10. Set `StashBackendURL` (and `StashAppKey` if used) in `StashShare/Info.plist`.

Share extensions do not run in the debugger from `flutter run`; build once, then share from Safari or Instagram on the device.

## 4. Optional: account and sync

1. Create a Supabase project and run `supabase/schema.sql` in the SQL editor.
2. Build with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
3. In the app: **⋮ → Account and sync**.

Local SQLite stays the source of truth. Sync is last-write-wins per row with tombstones for deletes. Learned suggestion rules stay on the device.

## Tests

```bash
cd backend && npm test
cd app && flutter test
```

To render the screens to PNGs for design review (seeded data, no device needed; written for Windows font paths):

```bash
cd app && flutter test test_screens --update-goldens
```

## Notes

- Building for Android on Windows from a very deep folder can fail with `impellerc … Could not write file` (the 260-character path limit). Keep the project in a short path.
- The URL rules exist three times (`backend/lib/urls.js`, `app/lib/services/link_parser.dart`, `app/ios/StashShare/LinkParser.swift`) and the SQLite schema twice (`app/lib/data/repo.dart`, `SharedStore.swift`). Change them together.
- Instagram thumbnail URLs expire after a while. The app caches images on disk, but very old previews can fall back to the generic thumbnail.
- `APP_KEY` ships inside the app binary, so it only deters casual abuse. Put real rate limiting or user auth in front of the backend before a public launch.
