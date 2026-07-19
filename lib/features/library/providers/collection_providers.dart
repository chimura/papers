import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/collection_dao.dart';

final collectionDaoProvider = Provider<CollectionDao>((ref) => CollectionDao());

final collectionsProvider = FutureProvider<List<CollectionRecord>>((ref) async {
  final dao = ref.read(collectionDaoProvider);
  return dao.getAll();
});

final allTagsProvider = FutureProvider<List<String>>((ref) async {
  final dao = ref.read(collectionDaoProvider);
  return dao.getAllTagNames();
});

/// Paper IDs belonging to a collection — used by the library list to apply
/// the collection filter.
final collectionPaperIdsProvider =
    FutureProvider.family<Set<int>, int>((ref, collectionId) async {
  final dao = ref.read(collectionDaoProvider);
  return (await dao.getPaperIdsInCollection(collectionId)).toSet();
});

/// Collection IDs a single paper belongs to — used by the assignment dialog.
final paperCollectionIdsProvider =
    FutureProvider.family<Set<int>, int>((ref, paperId) async {
  final dao = ref.read(collectionDaoProvider);
  return dao.getCollectionIdsForPaper(paperId);
});
