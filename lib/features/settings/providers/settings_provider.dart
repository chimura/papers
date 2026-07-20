import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

const _settingsKey = 'app_settings';

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_settingsKey);
    if (json != null) {
      return AppSettings.fromMap(jsonDecode(json) as Map<String, dynamic>);
    }
    return const AppSettings();
  }

  Future<void> _save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toMap()));
    state = AsyncData(settings);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final current = state.value ?? const AppSettings();
    await _save(current.copyWith(themeMode: mode));
  }

  Future<void> setAutoSync(bool enabled) async {
    final current = state.value ?? const AppSettings();
    await _save(current.copyWith(autoSyncEnabled: enabled));
  }

  Future<void> setSyncInterval(int minutes) async {
    final current = state.value ?? const AppSettings();
    await _save(current.copyWith(syncIntervalMinutes: minutes));
  }

  Future<void> setDefaultCitationStyle(DefaultCitationStyle style) async {
    final current = state.value ?? const AppSettings();
    await _save(current.copyWith(defaultCitationStyle: style));
  }

  Future<void> setShowAbstractInList(bool show) async {
    final current = state.value ?? const AppSettings();
    await _save(current.copyWith(showAbstractInList: show));
  }

  Future<void> setConfirmBeforeDelete(bool confirm) async {
    final current = state.value ?? const AppSettings();
    await _save(current.copyWith(confirmBeforeDelete: confirm));
  }

  Future<void> setPdfDarkMode(bool enabled) async {
    final current = state.value ?? const AppSettings();
    await _save(current.copyWith(pdfDarkMode: enabled));
  }

  Future<void> resetToDefaults() async {
    await _save(const AppSettings());
  }
}
