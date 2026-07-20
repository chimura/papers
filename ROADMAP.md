# Papers — Roadmap

Goal: a personal reference manager that rivals Mendeley, positioned exactly where
Mendeley lost user trust — **local-first, files in the user's own Google Drive,
zero lock-in** (annotations always exportable, `.bib` always fresh on disk).

Market notes (research, July 2026): Mendeley killed its desktop app in 2022 and the
replacement dropped watched folders, duplicate merge, full-text PDF search, and
continuous BibTeX sync — users still mourn these. Zotero's retention magnets are
Better BibTeX (stable citation keys + auto-exported `.bib`), the browser connector,
and retraction warnings. Mendeley's most-loved features are the Notebook
(cross-paper quotes with backlinks) and the Web Importer.

Statuses: `[ ]` todo · `[~]` in progress · `[x]` done. Keep this file updated as
items land.

---

## Prerequisite (do first)

- [x] **Schema migration scaffold** — `AppDatabase` now has `onUpgrade` driving
  a versioned `_migrations` map; `onCreate` always writes the latest schema.
  Covered by `test/database/migration_test.dart` (real v1 → v2 upgrade).

## Tier 1 — Quick wins (hours each) — **done 2026-07-20**

- [x] **Drag-and-drop import** — `desktop_drop` `DropTarget` over the library
  with a drop overlay; `.pdf` / `.bib` / `.ris` all supported via the shared
  `FileImportService.importPdf` (also used by the file picker) and the new
  `RisParserService`. Reports imported/skipped counts.
- [x] **Copy-citation shortcuts** — Ctrl+Shift+C formatted citation,
  Ctrl+Shift+B BibTeX, Ctrl+Shift+K `\cite{key}`, in both library (selected
  paper) and reader. Shared helpers in `citations/services/citation_clipboard.dart`.
- [x] **Reading position memory + Continue Reading shelf** — schema v2 columns,
  2s-debounced saves plus a flush on dispose, resume via `goToPage` on open,
  horizontal shelf with per-paper progress above the library list.
- [x] **Annotation export to Markdown** — `ExportService.toMarkdownSummary`
  (YAML frontmatter, citation, highlights blockquoted by page with color
  markers, notes). Copy/save per paper from the detail menu; bulk folder
  export in Settings.
- [x] **Find Open-Access PDF (Unpaywall)** — `UnpaywallService` with
  `%PDF-` magic-byte validation; single-paper action in the detail menu and a
  batch run in Settings for every DOI-bearing paper without a file.
- [x] **Pinnable deterministic citation keys** — `CitekeyService` with
  `[auth]/[Auth]/[year]/[shorttitle]/[veryshorttitle]` patterns, diacritics
  folding, and a/b/c → numeric collision suffixes. Generated on every insert;
  imported keys kept and auto-pinned; editable + pinning in the edit dialog;
  BibTeX export reads the stored key.
- [x] **Dark-mode PDF reading** — `ColorFiltered` inversion around the viewer
  with counter-inverted annotation colors, toggle in the reader app bar backed
  by `AppSettings.pdfDarkMode`.

## Tier 2 — Core Mendeley parity — **mostly done 2026-07-20**

Schema v3 added in one migration: `arxiv_id`, `pmid`, `read_status`,
`date_read`, `queue_position`, `needs_review`, `title_normalized` (+ index),
`update_status`, `update_notice_doi`, `published_version_doi`,
`updates_checked_at`, plus the `notes` (+`notes_fts`), `smart_collections`
and `auto_exports` tables.

### Capture

- [x] **Real PDF metadata extraction** — `MetadataExtractor.fromPdf` cascade:
  pdfrx headless text on pages 1–2 (DOI/arXiv regex) → raw-bytes XMP packet
  scan (`prism:doi`, `dc:title`) → first-page title guess verified against
  CrossRef at Dice ≥ 0.8. Wired into `FileImportService`, so every import
  route benefits. **Caveat: stage 1 is not unit-tested** (needs a real PDF
  with a text layer) — worth one manual check against a real paper.
- [x] **Watched import folder** — `WatchedFolderService` on `Directory.watch()`
  with a size-stability + open-lock settle loop (Windows holds the handle
  while a browser downloads). Folder picked in Settings; imports are flagged
  `needs_review` and filterable.
- [x] **Add-by-identifier: DOI + arXiv + PMID, bulk paste** — new Identifiers
  tab takes a mixed blob; `IdentifierResolverService` detects each type and
  resolves via CrossRef / arXiv Atom API / PubMed E-utilities, with add-all.
- [x] **Bulk BibTeX/RIS file import + PDF attach** — "Open .bib / .ris file"
  in the import screen (plus drag-and-drop) feeding the preview + add-all
  list, **and PDFs linked in the export come across automatically**: the
  BibTeX `file` field and RIS `L1`/`LK` link are parsed
  (`AttachmentPathParser` handles Zotero/Mendeley/JabRef escaping, Windows
  drive letters, and `file://` URIs), resolved absolute-or-relative to the
  export's folder, and copied into the library on import. This is the
  Mendeley/Zotero migration path. *Not done: per-entry "already in library"
  flags on the preview list.*
- [ ] **papers:// protocol + capture bookmarklet** — deferred; needs
  `protocol_handler` + `window_manager` and changes app launch behavior.

### Organize

- [x] **Bulk select + bulk edit** — long-press / checkbox multi-select with
  shift-click ranges and Ctrl+A, contextual action bar (favorite, read status,
  tag, add to collection, copy bibliography, delete), all batched in single
  transactions.
- [x] **Metadata Doctor** — `EnrichmentService` (CrossRef bibliographic search
  gated at Dice ≥ 0.9, Semantic Scholar batch endpoint, never overwrites
  existing values) run from Settings over every incomplete paper.
  *Not done: the field-by-field accept/reject dialog — it currently applies
  safe fills automatically; `EnrichmentService.diff` exists to build that UI.*
- [x] **Reading status** — unread/reading/read cycling from the list tile,
  auto-flip to "reading" when a PDF is opened, and a status filter.
  *Not done: the drag-reorderable "Read Next" queue view — `queue_position`
  and `saveQueueOrder` are in place, the UI is not.*
- [x] **Smart collections (saved searches)** — `LibraryFilter` is JSON
  round-trippable, saved by name to `smart_collections`, restored with one tap
  from the filter drawer.
- [x] **Nested collections (data layer)** — recursive-CTE subtree queries and
  cycle-safe re-parenting in `CollectionDao`. *Not done: the ExpansionTile
  tree + drag-to-reparent UI; the drawer still lists collections flat.*
- [x] **Retraction & preprint warnings** — `RetractionService` batches
  `works?filter=updates:` 20 DOIs at a time and reads `is-preprint-of` out of
  the stored CSL JSON; run from Settings, surfaced as a detail-screen banner
  and a struck-through title + icon in the list. *Not done: running it
  automatically on the sync timer.*

### Read & note

- [x] **Selection popup in the reader** — appears whenever text is selected:
  five instant-highlight swatches (no tool arming), Copy, "Copy with citation"
  (`"quote" (Author, Year, p. N)` + full reference), and "Add to notes".
  *Deviation: it is anchored bottom-center of the viewer rather than floating
  at the selection rect — reliable across zoom/scroll without transform math.*
- [x] **Per-paper Notebook with quote backlinks** — `notes`/`notes_fts` tables,
  `NoteDao` (incl. FTS search hardened the same way paper search is), a Notes
  tab on the paper detail screen, and quote capture from the reader that
  appends a blockquote with a `papers://open/{id}?page=n` backlink.
  *Not done: rendering Markdown (the editor is plain text) and making the
  backlinks clickable; cross-paper topic pages have DAO support but no UI.*
- [ ] **First-page thumbnails** — deferred.
- [ ] **Split view: two papers side by side** — deferred; needs the
  `readerStateProvider` → `.family` refactor.

### Write & cite

- [x] **Auto-synced `.bib` export** — register target files in Settings; a
  revision counter + 3s debounce rewrites them atomically (`.tmp` + rename)
  on every library change. *Not done: LaTeX escaping of `& % $ # _ { }` in
  `toBibtex` — still missing, and worth fixing before heavy LaTeX use.*
- [ ] **Rich-text citation copy (HTML clipboard)** — deferred: `super_clipboard`
  pulls in a Rust toolchain requirement, which is a real build-system risk on
  this machine. Revisit with `rich_clipboard` or a direct CF_HTML write.
- [x] **Bibliography builder** — select N papers → "Copy bibliography" produces
  one deduplicated list, alphabetical for author-date styles and numbered in
  selection order for IEEE. *Not done: saving to .html/.txt (clipboard only).*
- [ ] **Quick-cite global hotkey palette** — deferred; needs `hotkey_manager` +
  `tray_manager` and changes the app's close/lifecycle behavior.
- [x] **Document scan (engine)** — `DocumentScanService` resolves `[@key]` /
  `{@key}` placeholders against citation keys, renders in-text citations,
  appends a bibliography, and reports unresolved keys. *Not done: the screen
  to pick a file and write the `-formatted` copy — engine and tests only.*

## Tier 3 — Big bets (a week+ each)

- [ ] **PDF full-text search** (L) — `pdfrx_engine` headless text extraction per
  page into `pdf_text_fts` (FTS5, porter tokenizer) inside `Isolate.run`
  (sqflite writes on main isolate); search results show snippet + page, click
  jumps the reader there. The gap reviewers explicitly flag in today's Mendeley.
- [ ] **Duplicate detection + side-by-side merge** (L) — candidate passes:
  normalized DOI → arxiv_id → normalized title → year-blocked Dice similarity
  ≥0.9; merge in one transaction re-points annotations/tags/collections, keeps
  the better PDF; also run as a pre-check on every import. Consider a
  `merged_from_doi` column so Drive re-sync can't resurrect the loser.
- [ ] **Real CSL support (citeproc-js in QuickJS)** (L) — `flutter_js` bundle of
  citeproc.js; `papers.csl_json` column already stores near-CSL data from
  CrossRef (map `author`, `issued.date-parts`, type); fetch styles on demand
  from the Zotero styles repo (~10,000 journal styles). Replaces the 5
  hand-written styles at submission-quality fidelity.

---

## What's next

Tier 1 is complete; Tier 2 is complete except for the deferred items above.
Highest-value remaining work, roughly in order:

1. **LaTeX escaping in `toBibtex`** — small, and auto-export makes it matter.
2. **Manually verify PDF text extraction** against a few real papers
   (stage 1 of the extractor cascade has no unit test). Same for the
   Mendeley `file`-field PDF attach — unit-tested across formats, but worth
   one real Mendeley/Zotero export end-to-end.
3. **Markdown rendering + clickable backlinks in the Notebook** — the notes
   feature is functional but plain-text today.
4. **Read Next queue UI** and the **nested collections tree** — both have
   their data layers finished, only the widgets are missing.
5. **Metadata Doctor accept/reject dialog** using `EnrichmentService.diff`.
6. Then Tier 3 (full-text PDF search, duplicate merge, real CSL).

Deferred-with-reason: `papers://` protocol, quick-cite hotkey palette
(app-lifecycle risk), rich-text clipboard (Rust toolchain), thumbnails,
split view.

Full research digest and per-idea implementation notes: workflow run
`wf_9d455e48-632` (2026-07-19 session).

Full research digest and per-idea details: workflow run `wf_9d455e48-632`
(2026-07-19 session).
