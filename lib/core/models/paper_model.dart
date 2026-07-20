import 'author_model.dart';

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
  final List<AuthorModel> authors;
  final List<String> tags;
  final List<String> collections;

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
    this.authors = const [],
    this.tags = const [],
    this.collections = const [],
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
    List<AuthorModel>? authors,
    List<String>? tags,
    List<String>? collections,
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
      authors: authors ?? this.authors,
      tags: tags ?? this.tags,
      collections: collections ?? this.collections,
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
    };
  }

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
