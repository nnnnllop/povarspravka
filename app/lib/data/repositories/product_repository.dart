import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/calculation/models/product.dart';

class FoodGroup {
  final int id;
  final String code;
  final String name;

  const FoodGroup({
    required this.id,
    required this.code,
    required this.name,
  });

  factory FoodGroup.fromMap(Map<String, dynamic> map) {
    return FoodGroup(
      id: map['id'] as int? ?? 0,
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
    );
  }
}

class ProductRepository {
  static const String _schemaVersionPrefix = 'v3';
  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    final pending = _opening ??= _initDatabase();
    try {
      _db = await pending;
      return _db!;
    } finally {
      if (identical(_opening, pending)) _opening = null;
    }
  }

  Future<Database> _initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'povarspravka_reference.db');
    final versionPath = p.join(docsDir.path, 'povarspravka_reference.version');

    final file = File(dbPath);
    final versionFile = File(versionPath);

    final byteData = await rootBundle.load('assets/db/reference.db');
    final assetLength = byteData.lengthInBytes;
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final crc = getCrc32(bytes);
    final expectedMarker =
        '${_schemaVersionPrefix}_${assetLength}_${crc.toRadixString(16)}';

    bool needsCopy = !await file.exists();
    if (!needsCopy) {
      final localLen = await file.length();
      final savedMarker = await versionFile.exists()
          ? (await versionFile.readAsString()).trim()
          : '';
      if (localLen != assetLength || savedMarker != expectedMarker) {
        needsCopy = true;
      }
    }

    if (needsCopy) {
      // Удаляем старые WAL/SHM файлы перед перезаписью базы
      final walFile = File('$dbPath-wal');
      final shmFile = File('$dbPath-shm');
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      final tempFile = File('$dbPath.tmp');
      await tempFile.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await tempFile.rename(dbPath);
      await versionFile.writeAsString(expectedMarker, flush: true);
    }

    return await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: true,
    );
  }

  /// Поиск продуктов по названию и синонимам с использованием FTS5
  Future<List<Product>> searchProducts({
    required String query,
    int? groupId,
    String? source,
    int limit = 50,
  }) async {
    final db = await database;
    final cleanQuery = _normalizeQuery(query);

    List<Map<String, dynamic>> rows = [];

    if (cleanQuery.isEmpty) {
      String whereClause = '1=1';
      List<dynamic> whereArgs = [];

      if (groupId != null && groupId > 0) {
        whereClause += ' AND group_id = ?';
        whereArgs.add(groupId);
      }
      if (source != null && source.isNotEmpty) {
        whereClause += ' AND source = ?';
        whereArgs.add(source);
      }

      rows = await db.query(
        'product',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: "CASE WHEN source = 'skurikhin' THEN 0 ELSE 1 END, name ASC",
        limit: limit,
      );
    } else {
      // Подготовка FTS5 запроса с префиксным поиском по каждому слову
      final tokens = cleanQuery.split(' ').where((t) => t.isNotEmpty).toList();
      final ftsMatch = tokens.map((t) => '"$t"*').join(' ');

      String filterSql = '';
      List<dynamic> args = [ftsMatch];

      if (groupId != null && groupId > 0) {
        filterSql += ' AND p.group_id = ?';
        args.add(groupId);
      }
      if (source != null && source.isNotEmpty) {
        filterSql += ' AND p.source = ?';
        args.add(source);
      }

      final sql = '''
        SELECT p.*
        FROM product_fts fts
        JOIN product p ON p.id = CAST(fts.product_id AS INTEGER)
        WHERE product_fts MATCH ? $filterSql
        ORDER BY 
          CASE WHEN p.source = 'skurikhin' THEN 0 ELSE 1 END,
          bm25(product_fts) ASC,
          LENGTH(p.name) ASC
        LIMIT ?
      ''';
      args.add(limit);

      try {
        rows = await db.rawQuery(sql, args);
      } catch (_) {
        rows = [];
      }

      // Если FTS5 вернул пусто или произошла ошибка, выполняем fallback поиск по name_norm и таблице синонимов
      if (rows.isEmpty) {
        String fallbackWhere = '''
          (p.name_norm LIKE ? OR EXISTS (
            SELECT 1 FROM synonym s
            WHERE s.product_id = p.id
              AND (s.synonym_norm LIKE ? OR LOWER(s.synonym) LIKE ?)
          ))
        ''';
        final likePattern = '%$cleanQuery%';
        List<dynamic> fallbackArgs = [likePattern, likePattern, likePattern];

        if (groupId != null && groupId > 0) {
          fallbackWhere += ' AND p.group_id = ?';
          fallbackArgs.add(groupId);
        }
        if (source != null && source.isNotEmpty) {
          fallbackWhere += ' AND p.source = ?';
          fallbackArgs.add(source);
        }

        fallbackArgs.add(limit);

        rows = await db.rawQuery('''
          SELECT p.* FROM product p
          WHERE $fallbackWhere
          ORDER BY CASE WHEN p.source = 'skurikhin' THEN 0 ELSE 1 END, LENGTH(p.name) ASC, p.name ASC
          LIMIT ?
        ''', fallbackArgs);
      }
    }

    if (rows.isEmpty) return const [];

    // Пакетная загрузка мер продуктов одним запросом (без N+1)
    final productIds = rows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(productIds.length, '?').join(',');
    final measureRows = await db.rawQuery(
      'SELECT * FROM measure WHERE product_id IN ($placeholders) ORDER BY id ASC',
      productIds,
    );

    final measuresByProduct = <int, List<ProductMeasure>>{};
    for (final mRow in measureRows) {
      final measure = ProductMeasure.fromMap(mRow);
      measuresByProduct.putIfAbsent(measure.productId, () => []).add(measure);
    }

    return rows.map((row) {
      final pId = row['id'] as int;
      return Product.fromMap(row, measuresByProduct[pId] ?? const []);
    }).toList();
  }

  /// Получение мер одного продукта (штуки, ложки, стаканы)
  Future<List<ProductMeasure>> getMeasuresForProduct(int productId) async {
    final db = await database;
    final rows = await db.query(
      'measure',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'id ASC',
    );
    return rows.map((r) => ProductMeasure.fromMap(r)).toList();
  }

  /// Получение витаминов и минералов продукта из таблицы nutrient_value
  Future<List<ProductNutrient>> getNutrientsForProduct(int productId) async {
    final db = await database;
    final rows = await db.query(
      'nutrient_value',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'id ASC',
    );
    final result = <ProductNutrient>[];
    final seenCodes = <String>{};
    for (final row in rows) {
      final nutrient = ProductNutrient.fromMap(row);
      if (nutrient != null && seenCodes.add(nutrient.code)) {
        result.add(nutrient);
      }
    }
    return result;
  }

  /// Получение всех категорий продуктов
  Future<List<FoodGroup>> getFoodGroups() async {
    final db = await database;
    final rows = await db.query(
      'food_group',
      orderBy: 'id ASC',
    );
    return rows.map((r) => FoodGroup.fromMap(r)).toList();
  }

  static String _normalizeQuery(String q) {
    return q
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
