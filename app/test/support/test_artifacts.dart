import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Временная папка для артефактов теста (аудит D14).
///
/// Раньше тесты писали PDF/XLSX/снимки прямо в `../audit_artifacts/` и
/// `../audit/` рабочего дерева: после `flutter test` там оставался мусор,
/// а путь зависел от текущего каталога запуска и «протекал» между прогонами.
/// Теперь файлы живут в `Directory.systemTemp` и удаляются в `addTearDown`,
/// поэтому `git status` после тестов не меняется.
///
/// Вызывать только внутри теста (`addTearDown` вне теста запрещён).
Directory artifactDir(String name) =>
    artifactDirOnce(name).._registerCleanup();

extension _Cleanup on Directory {
  void _registerCleanup() => addTearDown(() => _deleteQuietly(this));
}

/// Временная папка без `addTearDown` — для `main()`/`setUpAll`, где
/// зарегистрировать tearDown нельзя. Удаляйте её сами (`tearDownAll`).
Directory artifactDirOnce(String name) =>
    Directory.systemTemp.createTempSync('povar_${name}_');

/// Удаление папки артефактов, не роняющее тест, если она уже удалена.
void _deleteQuietly(Directory dir) {
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}

/// Путь к файлу артефакта `fileName` во временном каталоге теста `name`.
File artifactFile(String name, String fileName) {
  final dir = artifactDir(name);
  return File('${dir.path}${Platform.pathSeparator}$fileName');
}
