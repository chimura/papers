import 'author_model.dart';

enum ReadStatus {
  unread('Unread'),
  reading('Reading'),
  read('Read');

  final String label;
  const ReadStatus(this.label);

  static ReadStatus fromName(String? name) => ReadStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => ReadStatus.unread,
      );
}

class PaperModel {
  final int? id;
  final String title;
  final String? abstract_;
  final String? doi;
  final String? year;
  final String? journal;
  final String? volume;
  final String? issue;
  final String? pages;
  final String? publisher;
  final String? url;
  final String? localPdfPath;
  final String? driveFileId;
  final bool isFavorite;
  final DateTime dateAdded;
  final DateTime dateModified;
  final String? cslJson;
  final String? bibtexKey;
  final bool bibtexKeyPinned;
  final int? lastReadPage;
  final double? lastReadZoom;
  final DateTime? lastReadAt;
  final int? totalPages;
  final String? arxivId;
  final String? pmid;
  final ReadStatus readStatus;
  final DateTime? dateRead;
  final int? queuePosition;
  final bool needsReview;
  final String? updateStatus;
  final String? updateNoticeDoi;
  final String? publishedVersionDoi;
  final DateTime? updatesCheckedAt;
  final List<AuthorModel> authors;
  final List<String> tags;
  final List<String> collections;

  /// A PDF path referenced by a BibTeX/RIS import, used only while importing
  /// to attach the file. Never persisted (absent from [toMap]/[fromMap]).
  final String? importedFilePath;

  const PaperModel({
    this.id,
    required this.title,
    this.abstract_,
    this.doi,
    this.year,
    this.journal,
    this.volume,
    this.issue,
    this.pages,
    this.publisher,
    this.url,
    this.localPdfPath,
    this.driveFileId,
    this.isFavorite = false,
    required this.dateAdded,
    required this.dateModified,
    this.cslJson,
    this.bibtexKey,
    this.bibtexKeyPinned = false,
    this.lastReadPage,
    this.lastReadZoom,
    this.lastReadAt,
    this.totalPages,
    this.arxivId,
    this.pmid,
    this.readStatus = ReadStatus.unread,
    this.dateRead,
    this.queuePosition,
    this.needsReview = false,
    this.updateStatus,
    this.updateNoticeDoi,
    this.publishedVersionDoi,
    this.updatesCheckedAt,
    this.authors = const [],
    this.tags = const [],
    this.collections = const [],
    this.importedFilePath,
  });

  PaperModel copyWith({
    int? id,
    String? title,
    String? abstract_,
    String? doi,
    String? year,
    String? journal,
    String? volume,
    String? issue,
    String? pages,
    String? publisher,
    String? url,
    String? localPdfPath,
    String? driveFileId,
    bool? isFavorite,
    DateTime? dateAdded,
    DateTime? dateModified,
    String? cslJson,
    String? bibtexKey,
    bool? bibtexKeyPinned,
    int? lastReadPage,
    double? lastReadZoom,
    DateTime? lastReadAt,
    int? totalPages,
    String? arxivId,
    String? pmid,
    ReadStatus? readStatus,
    DateTime? dateRead,
    int? queuePosition,
    bool? needsReview,
    String? updateStatus,
    String? updateNoticeDoi,
    String? publishedVersionDoi,
    DateTime? updatesCheckedAt,
    List<AuthorModel>? authors,
    List<String>? tags,
    List<String>? collections,
    String? importedFilePath,
  }) {
    return PaperModel(
      id: id ?? this.id,
      title: title ?? this.title,
      abstract_: abstract_ ?? this.abstract_,
      doi: doi ?? this.doi,
      year: year ?? this.year,
      journal: journal ?? this.journal,
      volume: volume ?? this.volume,
      issue: issue ?? this.issue,
      pages: pages ?? this.pages,
      publisher: publisher ?? this.publisher,
      url: url ?? this.url,
      localPdfPath: localPdfPath ?? this.localPdfPath,
      driveFileId: driveFileId ?? this.driveFileId,
      isFavorite: isFavorite ?? this.isFavorite,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      cslJson: cslJson ?? this.cslJson,
      bibtexKey: bibtexKey ?? this.bibtexKey,
      bibtexKeyPinned: bibtexKeyPinned ?? this.bibtexKeyPinned,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      lastReadZoom: lastReadZoom ?? this.lastReadZoom,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      totalPages: totalPages ?? this.totalPages,
      arxivId: arxivId ?? this.arxivId,
      pmid: pmid ?? this.pmid,
      readStatus: readStatus ?? this.readStatus,
      dateRead: dateRead ?? this.dateRead,
      queuePosition: queuePosition ?? this.queuePosition,
      needsReview: needsReview ?? this.needsReview,
      updateStatus: updateStatus ?? this.updateStatus,
      updateNoticeDoi: updateNoticeDoi ?? this.updateNoticeDoi,
      publishedVersionDoi: publishedVersionDoi ?? this.publishedVersionDoi,
      updatesCheckedAt: updatesCheckedAt ?? this.updatesCheckedAt,
      authors: authors ?? this.authors,
      tags: tags ?? this.tags,
      collections: collections ?? this.collections,
      importedFilePath: importedFilePath ?? this.importedFilePath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'abstract': abstract_,
      'doi': doi,
      'year': year,
      'journal': journal,
      'volume': volume,
      'issue': issue,
      'pages': pages,
      'publisher': publisher,
      'url': url,
      'local_pdf_path': localPdfPath,
      'drive_file_id': driveFileId,
      'is_favorite': isFavorite ? 1 : 0,
      'date_added': dateAdded.toIso8601String(),
      'date_modified': dateModified.toIso8601String(),
      'csl_json': cslJson,
      'bibtex_key': bibtexKey,
      'bibtex_key_pinned': bibtexKeyPinned ? 1 : 0,
      'last_read_page': lastReadPage,
      'last_read_zoom': lastReadZoom,
      'last_read_at': lastReadAt?.toIso8601String(),
      'total_pages': totalPages,
      'arxiv_id': arxivId,
      'pmid': pmid,
      'read_status': readStatus.name,
      'date_read': dateRead?.toIso8601String(),
      'queue_position': queuePosition,
      'needs_review': needsReview ? 1 : 0,
      'title_normalized': normalizedTitle,
      'update_status': updateStatus,
      'update_notice_doi': updateNoticeDoi,
      'published_version_doi': publishedVersionDoi,
      'updates_checked_at': updatesCheckedAt?.toIso8601String(),
    };
  }

  /// Lowercased, punctuation-stripped title used for fuzzy matching and
  /// duplicate detection. Kept in sync with AppDatabase.normalizeTitle.
  String get normalizedTitle => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static PaperModel fromMap(Map<String, dynamic> map) {
    return PaperModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      abstract_: map['abstract'] as String?,
      doi: map['doi'] as String?,
      year: map['year'] as String?,
      journal: map['journal'] as String?,
      volume: map['volume'] as String?,
      issue: map['issue'] as String?,
      pages: map['pages'] as String?,
      publisher: map['publisher'] as String?,
      url: map['url'] as String?,
      localPdfPath: map['local_pdf_path'] as String?,
      driveFileId: map['drive_file_id'] as String?,
      isFavorite: (map['is_favorite'] as int?) == 1,
      dateAdded: DateTime.parse(map['date_added'] as String),
      dateModified: DateTime.parse(map['date_modified'] as String),
      cslJson: map['csl_json'] as String?,
      bibtexKey: map['bibtex_key'] as String?,
      bibtexKeyPinned: (map['bibtex_key_pinned'] as int?) == 1,
      lastReadPage: map['last_read_page'] as int?,
      lastReadZoom: (map['last_read_zoom'] as num?)?.toDouble(),
      lastReadAt: map['last_read_at'] != null
          ? DateTime.parse(map['last_read_at'] as String)
          : null,
      totalPages: map['total_pages'] as int?,
      arxivId: map['arxiv_id'] as String?,
      pmid: map['pmid'] as String?,
      readStatus: ReadStatus.fromName(map['read_status'] as String?),
      dateRead: map['date_read'] != null
          ? DateTime.parse(map['date_read'] as String)
          : null,
      queuePosition: map['queue_position'] as int?,
      needsReview: (map['needs_review'] as int?) == 1,
      updateStatus: map['update_status'] as String?,
      updateNoticeDoi: map['update_notice_doi'] as String?,
      publishedVersionDoi: map['published_version_doi'] as String?,
      updatesCheckedAt: map['updates_checked_at'] != null
          ? DateTime.parse(map['updates_checked_at'] as String)
          : null,
    );
  }

  String get authorsFormatted {
    if (authors.isEmpty) return 'Unknown authors';
    if (authors.length == 1) return authors.first.displayName;
    if (authors.length == 2) {
      return '${authors[0].displayName} & ${authors[1].displayName}';
    }
    return '${authors.first.displayName} et al.';
  }

  String get citation {
    final parts = <String>[];
    parts.add(authorsFormatted);
    if (year != null) parts.add('($year)');
    parts.add(title);
    if (journal != null) parts.add(journal!);
    return parts.join('. ');
  }
}
