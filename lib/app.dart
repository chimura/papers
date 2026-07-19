import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/drive/auto_sync_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/providers/settings_provider.dart';

class SciApp extends ConsumerWidget {
  const SciApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(autoSyncControllerProvider);

    final settings = ref.watch(settingsProvider).value;
    final themeMode = settings?.themeMode.themeMode ?? ThemeMode.system;

    return MaterialApp.router(
      title: 'Sci',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
