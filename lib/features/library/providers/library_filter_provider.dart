import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/library_filter.dart';

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
  LibraryFilterNotifier.new,
);

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => const LibraryFilter();

  void setCollection(int? collectionId) {
    // Not copyWith: passing null there would keep the previous collection.
    state = LibraryFilter(
      collectionId: collectionId,
      tags: state.tags,
      yearFrom: state.yearFrom,
      yearTo: state.yearTo,
      favoritesOnly: state.favoritesOnly,
      sortBy: state.sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void toggleTag(String tag) {
    final tags = Set<String>.from(state.tags);
    if (tags.contains(tag)) {
      tags.remove(tag);
    } else {
      tags.add(tag);
    }
    state = state.copyWith(tags: tags);
  }

  void setYearRange(String? from, String? to) {
    state = state.copyWith(yearFrom: from, yearTo: to);
  }

  void toggleFavorites() {
    state = state.copyWith(favoritesOnly: !state.favoritesOnly);
  }

  void setSortBy(SortOption sort) {
    state = state.copyWith(sortBy: sort);
  }

  void toggleSortDirection() {
    state = state.copyWith(sortDescending: !state.sortDescending);
  }

  void clearAll() {
    state = state.clearFilters();
  }
}
