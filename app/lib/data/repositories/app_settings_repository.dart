import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Пользовательские настройки оформления и тактильного отклика.
class AppSettings {
  final ThemeMode themeMode;
  final bool hapticsEnabled;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.hapticsEnabled = true,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? hapticsEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'themeMode': themeMode.name,
        'hapticsEnabled': hapticsEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final modeRaw = json['themeMode'];
    final mode = switch (modeRaw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final haptics = json['hapticsEnabled'] is bool
        ? json['hapticsEnabled'] as bool
        : true;
    return AppSettings(themeMode: mode, hapticsEnabled: haptics);
  }
}

/// Локальное хранение [AppSettings] в `app_settings.json`.
class AppSettingsRepository {
  static const String _fileName = 'app_settings.json';
  final Directory? storageDirectory;
  Future<void> _tail = Future<void>.value();

  AppSettingsRepository({this.storageDirectory});

  Future<T> _serialized<T>(Future<T> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<File?> _resolveFile() async {
    Directory? dir = storageDirectory;
    if (dir == null) {
      try {
        dir = await getApplicationDocumentsDirectory();
      } on MissingPluginException {
        return null;
      } on UnsupportedError {
        return null;
      }
    }
    return File(p.join(dir.path, _fileName));
  }

  Future<AppSettings> load() => _serialized(() async {
        final file = await _resolveFile();
        if (file == null || !await file.exists()) {
          return const AppSettings();
        }
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) {
            return AppSettings.fromJson(decoded);
          }
        } catch (_) {}
        return const AppSettings();
      });

  Future<void> save(AppSettings settings) => _serialized(() async {
        final file = await _resolveFile();
        if (file == null) return;
        await file.parent.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path);
      });
}
