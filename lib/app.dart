import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/drive/auto_sync_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/citations/services/auto_bib_export.dart';
import 'features/import/providers/watched_folder_provider.dart';
import 'features/settings/providers/settings_provider.dart';

class SciApp extends ConsumerWidget {
  const SciApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Background workers that must live as long as the app.
    ref.watch(autoSyncControllerProvider);
    ref.watch(watchedFolderControllerProvider);
    ref.watch(autoBibExportProvider);

    final settings = ref.watch(settingsProvider).value;
    final themeMode = settings?.themeMode.themeMode ?? ThemeMode.system;

    return MaterialApp.router(
      title: 'Papers',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
