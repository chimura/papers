import '../../../core/models/paper_model.dart';

/// Generates Better BibTeX-style citation keys from paper metadata.
///
/// Pure logic: no I/O, no external dependencies.
class CitekeyService {
  /// Words ignored when building `[shorttitle]` / `[veryshorttitle]`.
  static const Set<String> _stopwords = {
    'a', 'an', 'the', 'of', 'on', 'in', 'for', 'with', 'and', 'or', 'to',
    'from', 'at', 'by', 'is', 'are',
  };

  /// Maps common Latin diacritics to their ASCII equivalents.
  static const Map<String, String> _diacriticsFold = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'æ': 'ae',
    'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ě': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
    'œ': 'oe',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u',
    'ý': 'y',
    'ß': 'ss',
    'ł': 'l',
    'ś': 's', 'š': 's',
    'ż': 'z', 'ź': 'z', 'ž': 'z',
    'č': 'c',
    'ř': 'r',
    'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
    'Æ': 'AE',
    'Ç': 'C',
    'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E', 'Ě': 'E',
    'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
    'Ñ': 'N',
    'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O', 'Ø': 'O',
    'Œ': 'OE',
    'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ů': 'U',
    'Ý': 'Y',
    'Ł': 'L',
    'Ś': 'S', 'Š': 'S',
    'Ż': 'Z', 'Ź': 'Z', 'Ž': 'Z',
    'Č': 'C',
    'Ř': 'R',
  };

  static final RegExp _tokenPattern = RegExp(r'\[([^\[\]]*)\]');
  static final RegExp _nonAlphanumeric = RegExp(r'[^a-zA-Z0-9]');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Generates a citation key for [paper] by substituting bracketed tokens
  /// in [pattern].
  ///
  /// Supported tokens: `[auth]`, `[Auth]`, `[year]`, `[shorttitle]`,
  /// `[veryshorttitle]`. Unknown bracketed tokens are dropped. Falls back to
  /// `'paper'` when the substituted result is empty.
  String generateKey(
    PaperModel paper, {
    String pattern = '[auth][year][shorttitle]',
  }) {
    final buffer = StringBuffer();
    var index = 0;
    for (final match in _tokenPattern.allMatches(pattern)) {
      if (match.start > index) {
        buffer.write(_clean(pattern.substring(index, match.start)));
      }
      buffer.write(_expandToken(match.group(1)!, paper));
      index = match.end;
    }
    if (index < pattern.length) {
      buffer.write(_clean(pattern.substring(index)));
    }

    final key = buffer.toString();
    return key.isEmpty ? 'paper' : key;
  }

  /// Returns [base] if it is not in [existingKeys]; otherwise appends the
  /// first free suffix: `a`..`z`, then `1`, `2`, ... Comparison is
  /// case-sensitive exact match.
  String ensureUnique(String base, Set<String> existingKeys) {
    if (!existingKeys.contains(base)) return base;

    final a = 'a'.codeUnitAt(0);
    final z = 'z'.codeUnitAt(0);
    for (var code = a; code <= z; code++) {
      final candidate = base + String.fromCharCode(code);
      if (!existingKeys.contains(candidate)) return candidate;
    }

    var suffix = 1;
    while (true) {
      final candidate = '$base$suffix';
      if (!existingKeys.contains(candidate)) return candidate;
      suffix++;
    }
  }

  String _expandToken(String token, PaperModel paper) {
    switch (token) {
      case 'auth':
        return _authorSlug(paper);
      case 'Auth':
        return _capitalize(_authorSlug(paper));
      case 'year':
        final year = paper.year;
        return year == null ? 'nd' : _clean(year);
      case 'shorttitle':
        return _titleWords(paper.title, 3).join();
      case 'veryshorttitle':
        return _titleWords(paper.title, 1).join();
      default:
        return '';
    }
  }

  String _authorSlug(PaperModel paper) {
    if (paper.authors.isEmpty) return 'unknown';
    final slug = _clean(paper.authors.first.familyName);
    return slug.isEmpty ? 'unknown' : slug;
  }

  /// Returns up to [count] non-stopword words of [title], each ASCII-folded,
  /// lowercased, and stripped of non-alphanumerics.
  List<String> _titleWords(String title, int count) {
    final words = <String>[];
    for (final raw in title.split(_whitespace)) {
      final word = _clean(raw);
      if (word.isEmpty || _stopwords.contains(word)) continue;
      words.add(word);
      if (words.length == count) break;
    }
    return words;
  }

  /// ASCII-folds, lowercases, and strips non-alphanumerics from [input].
  String _clean(String input) =>
      _fold(input).toLowerCase().replaceAll(_nonAlphanumeric, '');

  String _fold(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_diacriticsFold[char] ?? char);
    }
    return buffer.toString();
  }

  String _capitalize(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }
}
