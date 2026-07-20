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

## Tier 2 — Core Mendeley parity (a day or two each)

### Capture

- [ ] **Real PDF metadata extraction** (M) — cascade in `MetadataExtractor`:
  (1) `pdfrx` headless `loadText()` on pages 1–2, regex DOI/arXiv ID;
  (2) raw-bytes XMP block scan (`<x:xmpmeta>`, parse with `xml` package);
  (3) largest-font first-page line as title guess →
  `api.crossref.org/works?query.bibliographic=` with Dice-similarity acceptance
  (`string_similarity` package). Kills the filename-title failure mode.
- [ ] **Watched import folder** (M) — `Directory.watch()` (native
  ReadDirectoryChangesW on Windows); debounce + retry-open until the browser
  finishes writing; SHA-256 dedupe of seen files; reuse the PDF import pipeline;
  imports land flagged "needs review". Folder picked in Settings.
- [ ] **Add-by-identifier: DOI + arXiv + PMID, bulk paste** (M) — regex-detect ID
  type; arXiv export API (Atom XML), PubMed E-utilities (esummary/efetch),
  Semantic Scholar Graph API as cross-linker (`externalIds` gives DOI+arXiv+PMID
  for one paper). New columns `arxiv_id`, `pmid`; include in Drive manifest.
- [ ] **Bulk BibTeX/RIS file import** (M) — open whole `.bib`/`.ris` exports with
  preview table, per-entry "already in library" flags, one-transaction import;
  honor Zotero/JabRef `file = {...}` fields to attach PDFs from disk. This is
  the migration ramp for Mendeley/Zotero refugees.
- [ ] **papers:// protocol + capture bookmarklet** (M) — `protocol_handler` +
  `window_manager` packages; bookmarklet reads `citation_doi`/`citation_pdf_url`
  meta tags from publisher pages and opens `papers://import?...`. 80% of a web
  importer for 5% of the cost.

### Organize

- [ ] **Bulk select + bulk edit** (M) — Ctrl/Shift-click multi-select,
  contextual action bar (tag, collection, favorite, delete, enrich, find PDFs);
  batched DAO writes in one transaction. Force multiplier for everything else.
- [ ] **Metadata Doctor: batch enrichment** (M) — fill missing
  abstract/DOI/journal/year from CrossRef (`query.bibliographic` + Dice-verify)
  and Semantic Scholar batch endpoint (`POST /graph/v1/paper/batch`, 500 ids per
  request). Field-by-field accept/reject diff dialog.
- [ ] **Reading status + Read Next queue** (M) — `read_status`, `date_read`,
  `queue_position` columns; status chip cycles on tap; opening a PDF flips
  unread→reading; pinned "Recently Added" and reorderable "Read Next" views.
- [ ] **Smart collections (saved searches)** (M) — persist `LibraryFilter` +
  search text as JSON in a new `smart_collections` table; render with a bolt
  icon; tapping restores filter+search state. Include in Drive manifest.
- [ ] **Nested collections** (M) — `collections.parent_id` already exists;
  recursive CTE for subtree paper ids; ExpansionTile tree in the filter drawer;
  drag-to-reparent with cycle check.
- [ ] **Retraction & preprint warnings** (M) — CrossRef
  `works?filter=updates:{doi}` (batch ~20 per request) for
  retractions/corrections; `is-preprint-of` relation from the stored `csl_json`
  for "published version available" upgrade prompts. Red banner + list badge;
  run on the auto-sync timer.

### Read & note

- [ ] **Selection popup in the reader** (M) — floating toolbar above the text
  selection: 5 instant-highlight swatches, Copy, "Copy with citation"
  (`"quote" (Author, Year, p. N)` + full reference). All hooks
  (`onTextSelectionChange`, overlay scaling math) already exist.
- [ ] **Per-paper Notebook with quote backlinks** (M) — `notes` table
  (paper_id nullable → cross-paper topic pages) + `notes_fts`; Markdown editor
  (`flutter_markdown_plus`) with `papers://open/{id}?page=n` backlinks; "Add to
  Notebook" from highlights/selection popup. Mendeley's most-loved feature,
  minus the lock-in.
- [ ] **First-page thumbnails** (M) — render page 1 via pdfrx at import
  (serialize through a queue; pdfium isn't re-entrant), cache as PNG under
  `papers_pdfs/.thumbs/{id}.png`, show in grid tiles.
- [ ] **Split view: two papers side by side** (M) — extract a self-contained
  `ReaderPane` widget; convert `readerStateProvider` to a `.family` by paperId;
  resizable row layout.

### Write & cite

- [ ] **Auto-synced `.bib` export** (M) — register target paths
  (library or collection → file); a `libraryRevision` counter provider +
  3s-debounced atomic rewrite (`.tmp` + rename). Add LaTeX escaping to
  `toBibtex` (currently none: `& % $ # _ { }`). The Overleaf/LaTeX retention
  feature.
- [ ] **Rich-text citation copy (HTML clipboard)** (M) — `super_clipboard` for
  simultaneous HTML + plain text (italics survive pasting into Word/Docs);
  refactor `CitationStyle.format` to emit inline markup. Future-proofs for CSL.
- [ ] **Bibliography builder** (M) — multi-select → one sorted, deduplicated
  bibliography (alphabetical for author-date styles, numbered for IEEE) to
  clipboard or file.
- [ ] **Quick-cite global hotkey palette** (M) — `hotkey_manager` +
  `window_manager` + `tray_manager`: Ctrl+Alt+C anywhere on Windows pops a
  search palette over the current app; Enter copies the citation, Shift+Enter
  `\cite{key}`. Closest thing to Mendeley Cite with no plugin to break.
  Windows-only (guard on platform).
- [ ] **Document scan: placeholder citations** (M) — write `{@key}` /
  `{Author, Year}` in any editor; scan the file, replace with formatted
  citations + append bibliography, write a `-formatted` copy. `.txt`/`.md`
  trivial; `.rtf` via regex like Zotero does.

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

## Suggested build order

1. Prerequisite migration scaffold, then all of **Tier 1** (about a week total).
2. **Watched folder + real PDF extraction** (capture feels magical),
   **Notebook** (reading feels sticky), **auto-`.bib`** (writing feels pro).
3. Remaining Tier 2 by taste; Tier 3 when the foundations are stable.

Full research digest and per-idea details: workflow run `wf_9d455e48-632`
(2026-07-19 session).
