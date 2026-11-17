import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_haptics.dart';
import '../../data/repositories/app_settings_repository.dart';

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(),
);

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  final repo = ref.watch(appSettingsRepositoryProvider);
  return AppSettingsNotifier(repo);
});

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final AppSettingsRepository _repo;
  late final Future<void> _ready;
  Future<void> _saveQueue = Future<void>.value();
  bool _dirtyBeforeLoad = false;

  AppSettingsNotifier(this._repo) : super(const AppSettings()) {
    AppHaptics.enabled = state.hapticsEnabled;
    _ready = _load();
  }

  Future<void> _load() async {
    final loaded = await _repo.load();
    if (!mounted || _dirtyBeforeLoad) return;
    state = loaded;
    AppHaptics.enabled = loaded.hapticsEnabled;
  }

  Future<void> flush() async {
    await _ready;
    await _saveQueue;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state.themeMode == mode) return;
    _dirtyBeforeLoad = true;
    state = state.copyWith(themeMode: mode);
    await _enqueueSave(state);
  }

  Future<void> setHapticsEnabled(bool enabled) async {
    if (state.hapticsEnabled == enabled) return;
    _dirtyBeforeLoad = true;
    AppHaptics.enabled = enabled;
    state = state.copyWith(hapticsEnabled: enabled);
    await _enqueueSave(state);
  }

  Future<void> _enqueueSave(AppSettings snapshot) {
    final next = _saveQueue.then((_) => _repo.save(snapshot));
    _saveQueue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}
