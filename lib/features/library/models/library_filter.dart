import '../../../core/models/paper_model.dart';

enum SortOption {
  dateAdded('Date added', 'date_added'),
  title('Title', 'title'),
  year('Year', 'year'),
  author('Author', 'family_name');

  final String label;
  final String dbColumn;
  const SortOption(this.label, this.dbColumn);
}

class LibraryFilter {
  final int? collectionId;
  final Set<String> tags;
  final String? yearFrom;
  final String? yearTo;
  final bool favoritesOnly;
  final ReadStatus? readStatus;
  final bool missingPdfOnly;
  final bool needsReviewOnly;
  final SortOption sortBy;
  final bool sortDescending;

  const LibraryFilter({
    this.collectionId,
    this.tags = const {},
    this.yearFrom,
    this.yearTo,
    this.favoritesOnly = false,
    this.readStatus,
    this.missingPdfOnly = false,
    this.needsReviewOnly = false,
    this.sortBy = SortOption.dateAdded,
    this.sortDescending = true,
  });

  LibraryFilter copyWith({
    int? collectionId,
    Set<String>? tags,
    String? yearFrom,
    String? yearTo,
    bool? favoritesOnly,
    ReadStatus? readStatus,
    bool? missingPdfOnly,
    bool? needsReviewOnly,
    SortOption? sortBy,
    bool? sortDescending,
  }) {
    return LibraryFilter(
      collectionId: collectionId ?? this.collectionId,
      tags: tags ?? this.tags,
      yearFrom: yearFrom ?? this.yearFrom,
      yearTo: yearTo ?? this.yearTo,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      readStatus: readStatus ?? this.readStatus,
      missingPdfOnly: missingPdfOnly ?? this.missingPdfOnly,
      needsReviewOnly: needsReviewOnly ?? this.needsReviewOnly,
      sortBy: sortBy ?? this.sortBy,
      sortDescending: sortDescending ?? this.sortDescending,
    );
  }

  bool get isActive =>
      collectionId != null ||
      tags.isNotEmpty ||
      yearFrom != null ||
      yearTo != null ||
      favoritesOnly ||
      readStatus != null ||
      missingPdfOnly ||
      needsReviewOnly;

  LibraryFilter clearFilters() => LibraryFilter(
        sortBy: sortBy,
        sortDescending: sortDescending,
      );

  Map<String, dynamic> toJson() => {
        'collectionId': collectionId,
        'tags': tags.toList(),
        'yearFrom': yearFrom,
        'yearTo': yearTo,
        'favoritesOnly': favoritesOnly,
        'readStatus': readStatus?.name,
        'missingPdfOnly': missingPdfOnly,
        'needsReviewOnly': needsReviewOnly,
        'sortBy': sortBy.name,
        'sortDescending': sortDescending,
      };

  static LibraryFilter fromJson(Map<String, dynamic> json) => LibraryFilter(
        collectionId: json['collectionId'] as int?,
        tags: ((json['tags'] as List<dynamic>?) ?? const [])
            .map((t) => t as String)
            .toSet(),
        yearFrom: json['yearFrom'] as String?,
        yearTo: json['yearTo'] as String?,
        favoritesOnly: json['favoritesOnly'] as bool? ?? false,
        readStatus: json['readStatus'] != null
            ? ReadStatus.fromName(json['readStatus'] as String)
            : null,
        missingPdfOnly: json['missingPdfOnly'] as bool? ?? false,
        needsReviewOnly: json['needsReviewOnly'] as bool? ?? false,
        sortBy: SortOption.values.firstWhere(
          (s) => s.name == json['sortBy'],
          orElse: () => SortOption.dateAdded,
        ),
        sortDescending: json['sortDescending'] as bool? ?? true,
      );
}
