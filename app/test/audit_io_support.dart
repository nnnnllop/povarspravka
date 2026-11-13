// Общие утилиты аудита персистентности (persistence-fault-injector).
//
// Файл намеренно НЕ называется `*_test.dart`: он не содержит тестов и
// только импортируется файлами `audit_io_*_test.dart`.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

/// Имя основного файла библиотеки рецептов (фиксировано в
/// `DishStorageRepository._fileName`).
const String kMainName = 'povarspravka_user_dishes.json';

/// Самодостаточный продукт для тестов (не зависит от других файлов testsuite).
const Product auditBeet = Product(
  id: 1,
  code: '1',
  name: 'Свекла',
  groupId: 1,
  source: 'skurikhin',
  protein: 1.5,
  fat: .1,
  carbs: 8.8,
  kcal: 42,
);

Dish auditDish(double grams, {String id = 'beet', String title = ''}) => Dish(
      id: id,
      title: title,
      ingredients: [
        Ingredient(
            id: '$id-1', product: auditBeet, weightGrams: grams, isGross: false)
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// Корневой набор путей для одного временного каталога.
class StorePaths {
  final Directory dir;
  StorePaths(this.dir);
  File get main => File('${dir.path}${Platform.pathSeparator}$kMainName');
  File get bak => File('${main.path}.bak');
  File get tmp => File('${main.path}.tmp');
  File get bakTmp => File('${main.path}.bak.tmp');

  /// Все «лишние» файлы, кроме main/.bak/.tmp/.bak.tmp — утечка диска.
  Future<List<String>> strays() async {
    final out = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      final base = e.path.split(Platform.pathSeparator).last;
      const allowed = {
        kMainName,
        '$kMainName.bak',
        '$kMainName.tmp',
        '$kMainName.bak.tmp',
      };
      if (!allowed.contains(base)) out.add(base);
    }
    return out;
  }

  Future<List<String>> listNames() async {
    final out = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      out.add(e.path.split(Platform.pathSeparator).last);
    }
    out.sort();
    return out;
  }
}

Future<StorePaths> makeStore() async {
  final dir = await Directory.systemTemp.createTemp('povar_auditio_');
  addTearDown(() async {
    // Снимаем read-only, иначе Windows не даст удалить каталог.
    try {
      if (dir.existsSync()) {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              await e.setLastModified(e.lastModifiedSync());
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
  return StorePaths(dir);
}

/// Batched-исключение: возвращает объект ошибки или null.
Future<Object?> capture(Future<void> Function() f) async {
  try {
    await f();
    return null;
  } catch (e) {
    return e;
  }
}

Future<Object?> captureT<T>(Future<T> Function() f) async {
  try {
    await f();
    return null;
  } catch (e) {
    return e;
  }
}

/// Тип исключения в коротком виде для таблиц отчёта.
String errLabel(Object? e) {
  if (e == null) return '—';
  if (e is FormatException) return 'FormatException';
  if (e is FileSystemException) {
    return 'FileSystemException(${e.osError?.errorCode})';
  }
  if (e is ArgumentError) return 'ArgumentError';
  if (e is TypeError) return 'TypeError';
  return e.runtimeType.toString();
}

/// Пересчёт CRC-32 ровно тем же алгоритмом, что реализован в приватном
/// `DishStorageRepository._crc32` (полином 0xEDB88320, init/xorout 0xFFFFFFFF).
int crc32OfBytes(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

/// Эквивалент `DishStorageRepository._encode`, чтобы тест мог создать
/// документ с «правильной» CRC.
String encodeDocument(Map<String, dynamic> raw) {
  final payload = jsonEncode(raw);
  return jsonEncode({
    ...raw,
    'storageVersion': 1,
    'crc32': crc32OfBytes(utf8.encode(payload)),
  });
}

/// BOM-less копия `writeAsString(..., flush: true)` без перекодирования.
Future<void> writeBytes(File f, List<int> bytes) =>
    f.writeAsBytes(bytes, flush: true);

/// Побайтовое сравнение двух файлов.
Future<bool> sameBytes(File a, File b) async {
  final x = await a.readAsBytes();
  final y = await b.readAsBytes();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

/// Замена байт с сохранением длины (для тестов «битого» UTF-8).
Uint8List replaceRange(List<int> src, int start, List<int> ins) {
  final out = Uint8List.fromList([
    ...src.take(start),
    ...ins,
    ...src.skip(start + ins.length),
  ]);
  return out;
}
