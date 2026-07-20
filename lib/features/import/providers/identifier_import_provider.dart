import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paper_model.dart';
import '../services/identifier_resolver_service.dart';

final identifierResolverProvider = Provider<IdentifierResolverService>(
  (ref) => IdentifierResolverService(),
);

class IdentifierImportState {
  final bool isLoading;
  final List<PaperModel> papers;
  final List<String> unresolved;
  final String? error;

  const IdentifierImportState({
    this.isLoading = false,
    this.papers = const [],
    this.unresolved = const [],
    this.error,
  });
}

final identifierImportProvider =
    NotifierProvider<IdentifierImportNotifier, IdentifierImportState>(
  IdentifierImportNotifier.new,
);

class IdentifierImportNotifier extends Notifier<IdentifierImportState> {
  @override
  IdentifierImportState build() => const IdentifierImportState();

  /// Accepts a blob of mixed DOIs / arXiv ids / PMIDs and resolves each.
  Future<void> lookup(String blob) async {
    final service = ref.read(identifierResolverProvider);
    final ids = service.splitIdentifiers(blob);
    if (ids.isEmpty) {
      state = const IdentifierImportState(
          error: 'Paste one or more DOIs, arXiv IDs, or PMIDs');
      return;
    }

    state = const IdentifierImportState(isLoading: true);
    try {
      final papers = await service.resolveMany(ids);
      final resolvedIds = papers
          .expand((p) => [p.doi, p.arxivId, p.pmid])
          .whereType<String>()
          .map((s) => s.toLowerCase())
          .toSet();
      final unresolved = ids
          .where((id) => !resolvedIds.any((r) =>
              r.contains(id.toLowerCase()) || id.toLowerCase().contains(r)))
          .toList();

      state = IdentifierImportState(
        papers: papers,
        // Only report misses when the counts disagree; the containment test
        // above is a heuristic and should never invent failures.
        unresolved: papers.length == ids.length ? const [] : unresolved,
      );
    } catch (e) {
      state = IdentifierImportState(error: e.toString());
    }
  }

  void reset() => state = const IdentifierImportState();
}
