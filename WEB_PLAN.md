# Web app: status

Stash runs in a browser from the same Flutter code as the Android app. The built web app lives in
`backend/public/` and is served by the backend itself, at the server's own address.

## How it differs from the phone app

- **Adding posts**: there is no share menu in a browser, so links are pasted with "Add a link".
- **Previews**: a browser may not read other sites' pages, so previews come from the server only.
  YouTube works; Instagram and TikTok return little to a cloud server, so those posts often show
  without a cover or caption on the web.
- **Reminders, the home screen widget, opening posts in the platform's app**: phone only. On the
  web, "Open" opens the post in a new tab.
- **Data**: stored in this browser (SQLite compiled to WebAssembly). It is a separate library from
  the phone's; nothing syncs until real accounts and a database exist.

## Rebuilding after a change

From a short path (the Windows path limit applies to builds):

    cd app
    flutter build web --release
    # copy build/web/* to backend/public/, without the canvaskit/ folder (it loads from Google's CDN)

`web/sqlite3.wasm` and `web/sqflite_sw.js` are created once by `dart run sqflite_common_ffi_web:setup`.

Commit and push; Render redeploys the server with the new web app.

## Not done

- A wider desktop layout (the app is a phone-width column, capped at 1100 px).
- Translating phone-specific wording beyond the first-run screens.
