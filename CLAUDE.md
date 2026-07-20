# CLAUDE.md

**Papers** — a Flutter reference manager for researchers (Mendeley-style).
Windows desktop is the primary target; Android second. Local-first: SQLite
library, PDFs on disk, sync to the user's own Google Drive. No lock-in is a
product principle (annotations exportable, `.bib` on disk).

## Roadmap

**[ROADMAP.md](ROADMAP.md) is our agreed feature roadmap.** When asked to "work
on the roadmap" or pick the next feature, take the next unchecked item in tier
order (prerequisite → Tier 1 → 2 → 3) and update its checkbox status when done.

## Commands

- `flutter run -d windows` — run the app
- `flutter test` — all tests (DB tests run on the same SQLite FFI engine as Windows)
- `flutter analyze` — must stay at 0 issues
- `flutter build windows --debug` — binary at `build/windows/x64/runner/Debug/papers.exe`

## Architecture map

- `lib/core/database/` — `AppDatabase` (sqflite; FFI on desktop, initialized in
  `main.dart`) + DAOs. FTS5 index over papers with sync triggers. Schema changes
  need `_databaseVersion` bump + `onUpgrade` migration.
- `lib/core/auth/` — Firebase auth. Desktop uses an OAuth loopback flow
  (`desktop_google_auth.dart`, PKCE + local server) because google_sign_in has
  no Windows support; mobile uses google_sign_in v7 (needs `initialize()`).
  Desktop OAuth client credentials go in `desktop_oauth_config.dart`.
- `lib/core/drive/` — Drive sync: PDFs + JSON manifest in a visible "Papers"
  Drive folder. Order matters: pull manifest → push PDFs → pull PDFs → push
  manifest. `auto_sync_provider.dart` runs the periodic timer.
- `lib/features/` — feature folders (library, import, reader, citations,
  settings, auth), each with screens/providers/services/widgets. Riverpod
  (manual providers, no codegen), go_router with auth-gated redirect.

## Conventions & gotchas

- Registered IDs must not change: `com.sci.sci` (Android/iOS app IDs) and
  Firebase project `papers-sci` — they predate the sci→Papers rename.
- `PaperModel.copyWith` cannot clear a field to null; construct a new model
  when clearing (see `edit_paper_dialog.dart`).
- Author/tag relation changes go through `PaperDao.updatePaperWithRelations`,
  not `updatePaper`.
- User-visible sync/auth failures should surface as friendly messages
  (`GoogleSignInSetupException` pattern), not raw exceptions.
- Add tests for DAO/parser changes in `test/` — they run against real SQLite.
