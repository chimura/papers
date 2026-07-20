/// Pulls filesystem paths to attached PDFs out of the `file` field of a
/// BibTeX entry or the `L1`/`LK` link of an RIS record.
///
/// Reference managers each encode this differently, so the parser is
/// deliberately format-tolerant:
///  - Zotero: `Full Text PDF:/path/file.pdf:application/pdf`, colons in
///    Windows paths escaped as `\:` and backslashes doubled (`\\`); multiple
///    attachments separated by `;`.
///  - Mendeley: `:/path/file.pdf:pdf` (empty description), with Windows
///    backslashes written as the LaTeX escape `$\backslash$`.
///  - JabRef: `:relative/path.pdf:PDF`, path relative to the .bib directory.
///  - Any of them may use a `file://` URI with percent-encoding.
///
/// Only PDF paths are returned; other attachment types (snapshots, EPUBs)
/// are skipped. Returned paths may be absolute or relative — the caller
/// resolves relatives against the export file's directory.
class AttachmentPathParser {
  // A real Windows drive letter stands alone, so it must not be preceded by
  // another alphanumeric — otherwise the trailing "F" of "…PDF:/path" would
  // be read as drive "F:".
  static final _driveRe = RegExp(r'(?<![A-Za-z0-9])[A-Za-z]:[\\/]');

  /// Every PDF path referenced by one BibTeX `file` field value.
  static List<String> fromBibtexFileField(String raw) {
    return raw
        .split(';')
        .map(_extractPath)
        .whereType<String>()
        .toList();
  }

  /// The PDF path from an RIS `L1`/`LK` link value, or null.
  static String? fromRisLink(String raw) => _extractPath(raw);

  static String? _extractPath(String attachment) {
    var s = _normalizeEscapes(attachment).trim();
    if (s.isEmpty) return null;

    // Strip a file:// (or file:) URI scheme, keeping the leading slash of a
    // Unix path: `file:///home/x` -> `/home/x`, `file://C:/x` -> `C:/x`.
    final lower = s.toLowerCase();
    if (lower.startsWith('file://')) {
      s = s.substring(7);
    } else if (lower.startsWith('file:')) {
      s = s.substring(5);
    }

    // Leading ':' marks an empty description (Mendeley/JabRef).
    if (s.startsWith(':')) s = s.substring(1);

    final drive = _driveRe.firstMatch(s);
    if (drive != null) {
      // A Windows drive letter is an unambiguous path start, so anything
      // before it is a description label.
      s = s.substring(drive.start);
    } else {
      // No drive: drop a leading "description:" only when the description
      // can't itself be a path (contains no separators).
      final firstColon = s.indexOf(':');
      if (firstColon > 0) {
        final head = s.substring(0, firstColon);
        if (!head.contains('/') && !head.contains(r'\')) {
          s = s.substring(firstColon + 1);
        }
      }
    }

    // We only attach PDFs. Cutting at the extension also strips any trailing
    // `:mimetype`, sidestepping the unescaped-drive-colon ambiguity.
    final idx = s.toLowerCase().lastIndexOf('.pdf');
    if (idx == -1) return null;
    s = s.substring(0, idx + 4).trim();

    if (s.contains('%')) {
      try {
        s = Uri.decodeFull(s);
      } catch (_) {
        // Leave the raw form if it isn't valid percent-encoding.
      }
    }

    return s.isEmpty ? null : s;
  }

  static String _normalizeEscapes(String s) {
    return s
        .replaceAll(r'$\backslash$', r'\') // Mendeley
        .replaceAll(r'{\textbackslash}', r'\')
        .replaceAll(r'\\', r'\') // doubled separators
        .replaceAll(r'\:', ':') // Zotero-escaped colons
        .replaceAll(r'\{', '{')
        .replaceAll(r'\}', '}')
        .replaceAll(r'\_', '_')
        .replaceAll(r'\&', '&');
  }
}
