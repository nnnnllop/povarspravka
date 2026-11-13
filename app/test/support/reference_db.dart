import 'dart:io';

import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Справочная база приложения. Тесты запускаются из `app/`.
const String kReferenceDbPath = 'assets/db/reference.db';

/// Открывает `assets/db/reference.db` **только для чтения**
/// (`SQLITE_OPEN_READONLY`, то же, что `mode=ro`).
///
/// Пакет `sqflite_common_ffi` подключён только как `dev_dependency`: в
/// тестах нет платформенного плагина `sqflite`, а классификатор и эталон
/// проверяются на настоящих строках базы. Файл ассета тесты не меняют —
/// SHA-256 базы сверяется до и после прогона (отчёт 2026-11-03).
Future<Database> openReferenceDbReadOnly() async {
  final file = File(kReferenceDbPath);
  if (!file.existsSync()) {
    throw StateError(
        'Не найден $kReferenceDbPath: запускайте тесты из каталога app/');
  }
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    file.absolute.path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
}

/// Все продукты справочника в порядке `id` — тем же путём, что и
/// приложение (`SELECT p.* FROM product p` → [Product.fromMap]).
Future<List<Product>> loadAllReferenceProducts() async {
  final db = await openReferenceDbReadOnly();
  try {
    final rows =
        await db.rawQuery('SELECT p.* FROM product p ORDER BY p.id ASC');
    return [for (final row in rows) Product.fromMap(row)];
  } finally {
    await db.close();
  }
}

/// Сырые строки таблицы `product` (колонки базы как есть) — для генераторов,
/// которым нужны исходные значения (фаззер `reaudit_fuzz_property_test`).
Future<List<Map<String, Object?>>> loadAllReferenceRows() async {
  final db = await openReferenceDbReadOnly();
  try {
    final rows =
        await db.rawQuery('SELECT p.* FROM product p ORDER BY p.id ASC');
    return [for (final row in rows) Map<String, Object?>.of(row)];
  } finally {
    await db.close();
  }
}
