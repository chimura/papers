# Sci

A reference-management app for researchers, built with Flutter. Organize papers,
read and annotate PDFs, generate citations (APA/MLA/Chicago/Harvard/IEEE), and
back everything up to Google Drive.

Runs on Windows desktop and Android.

## Features

- **Library**: papers with authors, tags, favorites, filtering and full-text search (SQLite FTS5)
- **Import**: by DOI (CrossRef lookup), PDF file, or pasted BibTeX
- **Reader**: PDF viewer with highlight and note annotations
- **Citations**: formatted citations in 5 styles, BibTeX/RIS export
- **Sync**: PDFs + a JSON metadata manifest in a visible `Sci` folder in Google Drive

## Running on Windows

```powershell
flutter run -d windows
```

Sign-in options on the login screen:

- **Sign in with Google** — required for Drive sync. Needs a one-time OAuth
  client setup (below).
- **Continue without an account** — local-only library, no sync. Requires the
  *Anonymous* sign-in provider to be enabled in the
  [Firebase console](https://console.firebase.google.com/project/papers-sci/authentication/providers).

### One-time Google sign-in setup (Windows)

The `google_sign_in` plugin has no Windows implementation, so the app uses an
OAuth 2.0 loopback flow through your browser. It needs a **Desktop app** OAuth
client:

1. Open [Google Cloud console → Credentials](https://console.cloud.google.com/apis/credentials?project=papers-sci)
2. **Create Credentials → OAuth client ID → Application type: Desktop app**
3. Paste the client ID and secret into `lib/core/auth/desktop_oauth_config.dart`
   (or pass `--dart-define=GOOGLE_DESKTOP_CLIENT_ID=...` /
   `--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...` when building)
4. Make sure the **Google Drive API** is enabled for the project
   ([API library](https://console.cloud.google.com/apis/library/drive.googleapis.com?project=papers-sci))

## Tests

```powershell
flutter test
```

The database tests run against the same SQLite FFI engine the Windows app uses.
