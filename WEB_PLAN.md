# Web app: plan and status

Goal: run Stash in a browser from the same Flutter code as the Android app.

## Done

- [x] Web target added (`app/web/`), nothing else changed in the app.
- [x] Server answers browsers: CORS headers and `OPTIONS` preflight in `backend/server.js`.

## To do, in order

1. **Storage.** `sqflite` has no web support. Add `sqflite_common_ffi_web` and, on web, open the
   database with `databaseFactoryFfiWeb` (SQLite compiled to WebAssembly, stored in the browser).
   `Repo.open()` already accepts a `factory`; pass it from `main.dart` when `kIsWeb`.
   Needs `dart run sqflite_common_ffi_web:setup` once to copy the wasm files into `web/`.
2. **Remove `dart:io` from code the web build compiles.** It is used in:
   - `lib/config.dart` (`Platform.isAndroid` for the default server address)
   - `lib/data/repo.dart` (`defaultPath`, `path_provider_foundation`)
   - `lib/ui/post_card.dart` (`Platform.isAndroid` / `isIOS` in `openPost`)
   Replace with `kIsWeb` / `defaultTargetPlatform`, and move the iOS container path behind a
   conditional import.
3. **Previews.** A browser cannot fetch Instagram/TikTok pages itself (CORS), so on web
   `Api.metadata` must skip `DeviceMeta` and ask the server only. Known limit: the server gets
   little from Instagram and TikTok on Render, so web previews will be weaker than on the phone.
   YouTube works from the server.
4. **Things that do not exist in a browser.** Guard with `kIsWeb`:
   - share sheet and `MethodChannel`s (`stash/share`, `stash/open`, `stash/system`): on web the way
     in is "Add a link", which already exists
   - home screen widget (Android only)
   - reminders: `flutter_local_notifications` has limited web support; hide "Remind me" on web first
   - `Reminders.init()` and `SyncService.init()` at start-up
5. **Layout.** The app is phone-shaped. Constrain content to about 1100 px and let the folder and
   post grids use more columns (they already adapt to width).
6. **Build and host.** `flutter build web --dart-define=STASH_BACKEND_URL=...`, then serve
   `build/web` as a static site (Render static site, Firebase Hosting, or GitHub Pages).
7. **Data is per device.** The web app has its own empty library: nothing syncs with the phone
   until real accounts and a database exist (see the Firebase discussion).

## How to check each step

- `flutter analyze` and `flutter test` must stay green (Android must not regress).
- `flutter build web` must succeed, then open `build/web` through a local static server.
