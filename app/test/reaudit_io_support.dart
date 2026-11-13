// Независимый повторный аудит персистентности (persistence-auditor).
//
// Файл намеренно НЕ `*_test.dart`: он только импортируется тестами
// `reaudit_io_*_test.dart`. Не зависит от `audit_io_support.dart`, чтобы
// проверки не опирались на уже принятые допущения прежнего аудита.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

/// Имя основного файла библиотеки (`DishStorageRepository._fileName`).
const String kLib = 'povarspravka_user_dishes.json';

/// Дочерние файлы схемы «два документа».
const String kDraft = '$kLib.draft.json';

const Product kBeet = Product(
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

Dish mkDish({
  required String id,
  String title = '',
  double grams = 100,
  DateTime? at,
  int substitutes = 0,
}) {
  final t = at ?? DateTime.utc(2026, 1, 1);
  return Dish(
    id: id,
    title: title,
    ingredients: [
      Ingredient(id: '$id-i0', product: kBeet, weightGrams: grams),
      for (var i = 0; i < substitutes; i++)
        Ingredient(
          id: '$id-s$i',
          product: Product(
            id: 100 + i,
            code: '${100 + i}',
            name: 'Продукт $i',
            groupId: 1,
            source: 'skurikhin',
            protein: 1,
            fat: 1,
            carbs: 1,
            kcal: 17,
          ),
          weightGrams: 10.0 + i,
        ),
    ],
    createdAt: t,
    updatedAt: t,
  );
}

/// Ровно та же функция CRC-32, что `DishStorageRepository._crc32`
/// (полином 0xEDB88320, init/xorout 0xFFFFFFFF) — независимая копия.
int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

/// Канонический документ с CRC, как его пишет `_encode`.
String encodeDoc(Map<String, dynamic> raw) {
  final payload = jsonEncode(raw);
  return jsonEncode({
    ...raw,
    'storageVersion': 1,
    'crc32': crc32(utf8.encode(payload)),
  });
}

String encodeDraftDoc(Object? draft) =>
    encodeDoc(<String, dynamic>{'activeDraft': draft});

class Store {
  final Directory dir;
  Store(this.dir);
  String p(String name) => '${dir.path}${Platform.pathSeparator}$name';
  File f(String name) => File(p(name));
  File get lib => f(kLib);
  File get libBak => f('$kLib.bak');
  File get libTmp => f('$kLib.tmp');
  File get draft => f(kDraft);
  File get draftBak => f('$kDraft.bak');

  List<String> namesSync() {
    final out = <String>[];
    for (final e in dir.listSync(followLinks: false)) {
      out.add(e.path.split(Platform.pathSeparator).last);
    }
    out.sort();
    return out;
  }
}

/// Временный каталог в `%TEMP%\povar_reaudit\io\` (не в проекте).
final Directory kScratchRoot = () {
  final d = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}povar_reaudit'
      '${Platform.pathSeparator}io');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}();

Future<Store> newStore([String tag = 'st']) async {
  final dir = await kScratchRoot.createTemp('${tag}_');
  addTearDown(() async {
    try {
      await _unlockTree(dir);
      await dir.delete(recursive: true);
    } catch (_) {}
  });
  return Store(dir);
}

Future<void> _unlockTree(Directory dir) async {
  try {
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          await e.setLastModified(DateTime.now());
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// Снять read-only / вернуть права на файл (Windows: `attrib -R`).
void toWritable(String path) =>
    Process.runSync('attrib', ['-R', path], runInShell: false);
void toReadOnly(String path) =>
    Process.runSync('attrib', ['+R', path], runInShell: false);

Future<Object?> captureErr(Future<void> Function() f) async {
  try {
    await f();
    return null;
  } on Object catch (e) {
    return e;
  }
}

Future<Botched<T>> captureT<T>(Future<T> Function() f) async {
  try {
    return Botched<T>(await f(), null);
  } on Object catch (e) {
    return Botched<T>(null, e);
  }
}

class Botched<T> {
  final T? value;
  final Object? error;
  Botched(this.value, this.error);
  bool get ok => error == null;
}

String errLabel(Object? e) {
  if (e == null) return '—';
  if (e is FormatException) return 'FormatException';
  if (e is FileSystemException) {
    return 'FileSystemException(${e.osError?.errorCode})';
  }
  if (e is ArgumentError) return 'ArgumentError';
  if (e is StateError) return 'StateError';
  if (e is TypeError) return 'TypeError';
  return e.runtimeType.toString();
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Проверяет, что снимок байт — целый документ библиотеки с валидным CRC.
/// Возвращает (ok, сообщение).
(bool, String) verifyLibrarySnapshot(Uint8List bytes) {
  if (bytes.isEmpty) return (false, 'empty');
  final Map<String, dynamic> doc;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return (false, 'not-an-object');
    doc = decoded;
  } catch (e) {
    return (false, 'unparsable:${e.runtimeType}');
  }
  if (!doc.containsKey('crc32') || !doc.containsKey('storageVersion')) {
    return (false, 'legacy-or-malformed');
  }
  final v = doc.remove('storageVersion');
  final c = doc.remove('crc32');
  if (v != 1) return (false, 'version=$v');
  if (c != crc32(utf8.encode(jsonEncode(doc)))) return (false, 'crc-mismatch');
  if (doc['savedDishes'] is! List) return (false, 'no-savedDishes');
  return (true, 'ok');
}

(bool, String) verifyDraftSnapshot(Uint8List bytes) {
  if (bytes.isEmpty) return (false, 'empty');
  final Map<String, dynamic> doc;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return (false, 'not-an-object');
    doc = decoded;
  } catch (e) {
    return (false, 'unparsable:${e.runtimeType}');
  }
  if (!doc.containsKey('crc32') || !doc.containsKey('storageVersion')) {
    return (false, 'legacy-or-malformed');
  }
  final v = doc.remove('storageVersion');
  final c = doc.remove('crc32');
  if (v != 1) return (false, 'version=$v');
  if (c != crc32(utf8.encode(jsonEncode(doc)))) return (false, 'crc-mismatch');
  if (!doc.containsKey('activeDraft')) return (false, 'no-activeDraft');
  return (true, 'ok');
}

/// Детерминированный ГПСЧ для воспроизводимых документов.
Random seeded(int s) => Random(s);

String randomTitle(Random r, int maxLen) {
  const alphabet = 'абвгдеёжзийклмнопрстуфхцчшщыэюя abc-🍲é\u0301«»';
  final n = r.nextInt(maxLen + 1);
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    final rv = r.nextInt(alphabet.length);
    b.write(alphabet[rv]);
  }
  return b.toString();
}
