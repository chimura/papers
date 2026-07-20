import 'package:flutter/material.dart';

enum AppThemeMode {
  system('System', ThemeMode.system),
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark);

  final String label;
  final ThemeMode themeMode;
  const AppThemeMode(this.label, this.themeMode);
}

enum DefaultCitationStyle { apa, mla, chicago, ieee, harvard }

class AppSettings {
  static const defaultCitationKeyPattern = '[auth][year][veryshorttitle]';

  final AppThemeMode themeMode;
  final bool autoSyncEnabled;
  final int syncIntervalMinutes;
  final DefaultCitationStyle defaultCitationStyle;
  final bool showAbstractInList;
  final bool confirmBeforeDelete;
  final bool pdfDarkMode;
  final String citationKeyPattern;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.autoSyncEnabled = false,
    this.syncIntervalMinutes = 30,
    this.defaultCitationStyle = DefaultCitationStyle.apa,
    this.showAbstractInList = false,
    this.confirmBeforeDelete = true,
    this.pdfDarkMode = false,
    this.citationKeyPattern = defaultCitationKeyPattern,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? autoSyncEnabled,
    int? syncIntervalMinutes,
    DefaultCitationStyle? defaultCitationStyle,
    bool? showAbstractInList,
    bool? confirmBeforeDelete,
    bool? pdfDarkMode,
    String? citationKeyPattern,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      defaultCitationStyle: defaultCitationStyle ?? this.defaultCitationStyle,
      showAbstractInList: showAbstractInList ?? this.showAbstractInList,
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
      pdfDarkMode: pdfDarkMode ?? this.pdfDarkMode,
      citationKeyPattern: citationKeyPattern ?? this.citationKeyPattern,
    );
  }

  Map<String, dynamic> toMap() => {
        'themeMode': themeMode.name,
        'autoSyncEnabled': autoSyncEnabled,
        'syncIntervalMinutes': syncIntervalMinutes,
        'defaultCitationStyle': defaultCitationStyle.name,
        'showAbstractInList': showAbstractInList,
        'confirmBeforeDelete': confirmBeforeDelete,
        'pdfDarkMode': pdfDarkMode,
        'citationKeyPattern': citationKeyPattern,
      };

  static AppSettings fromMap(Map<String, dynamic> map) => AppSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (t) => t.name == map['themeMode'],
          orElse: () => AppThemeMode.system,
        ),
        autoSyncEnabled: map['autoSyncEnabled'] as bool? ?? false,
        syncIntervalMinutes: map['syncIntervalMinutes'] as int? ?? 30,
        defaultCitationStyle: DefaultCitationStyle.values.firstWhere(
          (s) => s.name == map['defaultCitationStyle'],
          orElse: () => DefaultCitationStyle.apa,
        ),
        showAbstractInList: map['showAbstractInList'] as bool? ?? false,
        confirmBeforeDelete: map['confirmBeforeDelete'] as bool? ?? true,
        pdfDarkMode: map['pdfDarkMode'] as bool? ?? false,
        citationKeyPattern: map['citationKeyPattern'] as String? ??
            defaultCitationKeyPattern,
      );
}
