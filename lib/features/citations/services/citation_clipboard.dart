import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/models/paper_model.dart';
import '../../library/providers/library_provider.dart';
import '../../settings/models/app_settings.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/citation_style.dart';
import '../styles/apa_style.dart';
import '../styles/chicago_style.dart';
import '../styles/harvard_style.dart';
import '../styles/ieee_style.dart';
import '../styles/mla_style.dart';
import 'citekey_service.dart';
import 'export_service.dart';

CitationStyle citationStyleFor(DefaultCitationStyle style) {
  switch (style) {
    case DefaultCitationStyle.apa:
      return ApaStyle();
    case DefaultCitationStyle.mla:
      return MlaStyle();
    case DefaultCitationStyle.chicago:
      return ChicagoStyle();
    case DefaultCitationStyle.ieee:
      return IeeeStyle();
    case DefaultCitationStyle.harvard:
      return HarvardStyle();
  }
}

/// Makes sure [paper] has a stored citation key, generating and persisting
/// one when missing (for papers imported before keys existed).
Future<PaperModel> ensureCitationKey(WidgetRef ref, PaperModel paper) async {
  final key = paper.bibtexKey;
  if (key != null && key.isNotEmpty) return paper;

  final dao = ref.read(paperDaoProvider);
  final service = CitekeyService();
  final pattern = ref.read(settingsProvider).value?.citationKeyPattern ??
      AppSettings.defaultCitationKeyPattern;
  final newKey = service.ensureUnique(
    service.generateKey(paper, pattern: pattern),
    await dao.getAllBibtexKeys(),
  );

  if (paper.id != null) {
    await dao.setBibtexKey(paper.id!, newKey, pinned: false);
    await ref.read(libraryProvider.notifier).refresh();
  }
  return paper.copyWith(bibtexKey: newKey);
}

Future<void> copyFormattedCitation(
    WidgetRef ref, BuildContext context, PaperModel paper) async {
  final styleEnum = ref.read(settingsProvider).value?.defaultCitationStyle ??
      DefaultCitationStyle.apa;
  final style = citationStyleFor(styleEnum);
  await Clipboard.setData(ClipboardData(text: style.format(paper)));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${style.shortName} citation copied')),
    );
  }
}

Future<void> copyBibtexEntry(
    WidgetRef ref, BuildContext context, PaperModel paper) async {
  final withKey = await ensureCitationKey(ref, paper);
  await Clipboard.setData(
    ClipboardData(text: ExportService().toBibtex(withKey)),
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('BibTeX entry copied')),
    );
  }
}

Future<void> copyCiteCommand(
    WidgetRef ref, BuildContext context, PaperModel paper) async {
  final withKey = await ensureCitationKey(ref, paper);
  await Clipboard.setData(
    ClipboardData(text: '\\cite{${withKey.bibtexKey}}'),
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('\\cite{${withKey.bibtexKey}} copied')),
    );
  }
}
