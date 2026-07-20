import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Multi-selection state for bulk actions in the library.
final selectionProvider =
    NotifierProvider<SelectionNotifier, Set<int>>(SelectionNotifier.new);

class SelectionNotifier extends Notifier<Set<int>> {
  int? _anchorId;

  @override
  Set<int> build() => const {};

  bool get isActive => state.isNotEmpty;

  void toggle(int paperId) {
    final next = Set<int>.from(state);
    if (!next.remove(paperId)) next.add(paperId);
    _anchorId = paperId;
    state = next;
  }

  /// Shift-click: selects everything between the last clicked row and this
  /// one, using the currently displayed (filtered, sorted) order.
  void selectRangeTo(int paperId, List<int> orderedIds) {
    final anchor = _anchorId;
    if (anchor == null || anchor == paperId) {
      toggle(paperId);
      return;
    }
    final start = orderedIds.indexOf(anchor);
    final end = orderedIds.indexOf(paperId);
    if (start < 0 || end < 0) {
      toggle(paperId);
      return;
    }
    final range = start <= end
        ? orderedIds.sublist(start, end + 1)
        : orderedIds.sublist(end, start + 1);
    state = {...state, ...range};
    _anchorId = paperId;
  }

  void selectAll(List<int> ids) => state = ids.toSet();

  void clear() {
    _anchorId = null;
    state = const {};
  }
}
