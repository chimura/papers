import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/settings_provider.dart';
import '../auth/auth_provider.dart';
import 'drive_provider.dart';
import 'drive_sync_service.dart';

/// Runs Drive sync periodically while auto-sync is enabled in Settings and a
/// Google account is signed in. Watch this provider once (SciApp does) to
/// keep the timer alive; it rebuilds itself when settings or auth change.
final autoSyncControllerProvider = Provider<void>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final user = ref.watch(authStateProvider).value;

  final enabled = settings?.autoSyncEnabled ?? false;
  final hasGoogleAccount = user != null && !user.isAnonymous;
  if (!enabled || !hasGoogleAccount) return;

  final interval = Duration(minutes: settings!.syncIntervalMinutes);
  final timer = Timer.periodic(interval, (_) {
    final current = ref.read(syncStateProvider);
    if (current.status != SyncStatus.syncing) {
      ref.read(syncStateProvider.notifier).sync();
    }
  });

  ref.onDispose(timer.cancel);
});
