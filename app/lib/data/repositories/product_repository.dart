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
  /// v5: в базе появилась колонка `product.is_dish` (этап 6). Префикс
  /// входит в маркер версии, поэтому у пользователей с прежней копией база
  /// перекопируется из ассета.
  static const String _schemaVersionPrefix = 'v5';
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
    bool? isDish,
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
      if (isDish != null) {
        whereClause += ' AND is_dish = ?';
        whereArgs.add(isDish ? 1 : 0);
      }

      rows = await db.query(
        'product',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: "is_dish ASC, "
            "CASE WHEN source = 'skurikhin' THEN 0 ELSE 1 END, name ASC",
        limit: limit,
      );
    } else {
      // Подготовка FTS5 запроса с префиксным поиском по каждому слову.
      //
      // Усечённая основа нужна для беглых гласных: префикс "сырок"* НЕ
      // находит «сырки» (другая основа — «сырк»), из-за чего поиск «сырок»
      // отдавал «Колбасу сырокопченую» вместо творожных сырков.
      final tokens =
          cleanQuery.split(' ').where((t) => t.isNotEmpty).toList();
      final stemmed = tokens.map(_stemToken).toList();
      // Дефект D10: префикс «морс*» цепляет «морской» («Окунь морской»).
      // Поэтому для запросов длиной ≥ 4 в первом проходе ищется ЦЕЛОЕ слово
      // (без `*`), а префиксный проход по усечённой основе остаётся вторым —
      // он дотягивается до словоформ («сырок» → «сырки»).
      final firstPassExact = tokens.every((t) => t.length >= 4);
      final ftsMatchExact = tokens
          .map((t) => firstPassExact ? '"$t"' : '"$t"*')
          .join(' ');
      final ftsMatchStem = stemmed.map((t) => '"$t"*').join(' ');

      String filterSql = '';
      List<dynamic> args = [];

      if (groupId != null && groupId > 0) {
        filterSql += ' AND p.group_id = ?';
        args.add(groupId);
      }
      if (source != null && source.isNotEmpty) {
        filterSql += ' AND p.source = ?';
        args.add(source);
      }
      if (isDish != null) {
        filterSql += ' AND p.is_dish = ?';
        args.add(isDish ? 1 : 0);
      }

      // Ранжирование (дефект H3): сначала продукт, чьё НАЗВАНИЕ равно
      // запросу; затем целое слово в названии; затем целое слово в
      // синониме («сырок» → «Сырки глазированные»); затем начало слова;
      // затем подстрока. Внутри группы — Скурихин раньше BLS, bm25, длина.
      // Этап 6: `is_dish ASC` стоит ВПЕРВЫЕ и срабатывает даже без фильтра —
      // сырьё выше готовых блюд.
      final sql = '''
        SELECT p.*
        FROM product_fts fts
        JOIN product p ON p.id = CAST(fts.product_id AS INTEGER)
        WHERE product_fts MATCH ? $filterSql
        ORDER BY
          p.is_dish ASC,
          CASE
            WHEN p.name_norm = ? THEN 0
            WHEN (' ' || p.name_norm || ' ') LIKE ? THEN 1
            WHEN (' ' || fts.name_norm || ' ') LIKE ? THEN 2
            WHEN p.name_norm LIKE ? THEN 3
            WHEN p.name_norm LIKE ? THEN 4
            ELSE 5
          END ASC,
          CASE WHEN p.name_norm LIKE ? THEN 0 ELSE 1 END ASC,
          CASE WHEN p.source = 'skurikhin' THEN 0 ELSE 1 END,
          bm25(product_fts, 10.0, 1.0) ASC,
          LENGTH(p.name) ASC
        LIMIT ?
      ''';

      Future<List<Map<String, Object?>>> runMatch(String match) {
        final orderArgs = <dynamic>[
          match,
          ...args,
          cleanQuery,
          '% $cleanQuery %',
          '% $cleanQuery %',
          '$cleanQuery %',
          '%$cleanQuery%',
          '%$cleanQuery%',
          limit,
        ];
        return db.rawQuery(sql, orderArgs);
      }

      try {
        // 1) как написано: «сода» не должна цеплять «содержанием»
        rows = List<Map<String, dynamic>>.of(await runMatch(ftsMatchExact));
        // 2) добираем прочие словоформы, если первый проход не набрал лимит
        if (rows.length < limit && ftsMatchStem != ftsMatchExact) {
          final seen = rows.map((r) => r['id'] as int).toSet();
          final more = await runMatch(ftsMatchStem);
          for (final row in more) {
            if (seen.add(row['id'] as int)) rows.add(row);
            if (rows.length >= limit) break;
          }
        }
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
        if (isDish != null) {
          fallbackWhere += ' AND p.is_dish = ?';
          fallbackArgs.add(isDish ? 1 : 0);
        }

        fallbackArgs.add(limit);

        rows = await db.rawQuery('''
          SELECT p.* FROM product p
          WHERE $fallbackWhere
          ORDER BY p.is_dish ASC,
                   CASE WHEN p.source = 'skurikhin' THEN 0 ELSE 1 END,
                   LENGTH(p.name) ASC, p.name ASC
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

  /// Получение всех категорий продуктов.
  ///
  /// `isDish`: `false` — только группы, где есть продукты-сырьё, `true` —
  /// только группы с готовыми блюдами, `null` — все группы (этап 6).
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async {
    final db = await database;
    if (isDish == null) {
      final rows = await db.query('food_group', orderBy: 'id ASC');
      return rows.map((r) => FoodGroup.fromMap(r)).toList();
    }
    final rows = await db.rawQuery(
      'SELECT g.* FROM food_group g '
      'WHERE EXISTS (SELECT 1 FROM product p '
      '              WHERE p.group_id = g.id AND p.is_dish = ?) '
      'ORDER BY g.id ASC',
      [isDish ? 1 : 0],
    );
    return rows.map((r) => FoodGroup.fromMap(r)).toList();
  }

  /// Сколько продуктов всего (этап 6: с учётом фильтра «блюдо/сырьё»).
  Future<int> getTotalCount({bool? isDish, String? source}) async {
    final db = await database;
    final where = StringBuffer('1=1');
    final args = <dynamic>[];
    if (isDish != null) {
      where.write(' AND is_dish = ?');
      args.add(isDish ? 1 : 0);
    }
    if (source != null && source.isNotEmpty) {
      where.write(' AND source = ?');
      args.add(source);
    }
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS n FROM product WHERE $where',
            args);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Сколько продуктов по каждому источнику (этап 6).
  Future<Map<String, int>> getCountBySource({bool? isDish}) async {
    final db = await database;
    final sql = isDish == null
        ? 'SELECT source, COUNT(*) AS n FROM product GROUP BY source'
        : 'SELECT source, COUNT(*) AS n FROM product WHERE is_dish = ? '
            'GROUP BY source';
    final rows = isDish == null
        ? await db.rawQuery(sql)
        : await db.rawQuery(sql, [isDish ? 1 : 0]);
    return {
      for (final row in rows)
        (row['source'] as String? ?? ''): (row['n'] as num?)?.toInt() ?? 0,
    };
  }

  static String _normalizeQuery(String q) {
    return q
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Усечение токена для FTS5-префикса (зеркало `_fts_tokens` в
  /// `tools/data_pipeline/build_reference_db.py`).
  ///
  /// FTS5-префикс "сырок"* НЕ находит «сырки»: у слова беглое гласное и
  /// другая основа — «сырк». Поэтому отбрасывается конечное окончание
  /// (гласные/«й»/«ь» подряд) («гречка» → «гречк») и беглое гласное перед «к»
  /// («сырок» → «сырк», и «сырок», и «сырки» дают одну основу). Короткие
  /// токены (≤ 3) не трогаются, иначе «сыр» совпадёт с «сырок».
  ///
  /// Этап 6.6: окончание отсекается ЦИКЛОМ, а не одним символом. Раньше
  /// «куриный» → «курины» (в базе только «куриная»/«куриное»), «говяжий» →
  /// «говяжи» (в базе «говяжья»), «свиная» → «свина» (в базе «свиной»), и
  /// запрос «окорочок куриный» отдавал ПУСТО. Теперь прилагательные всех
  /// родов сходятся к одной основе: «куриный»/«куриная»/«куриное» → «курин»,
  /// «говяжий»/«говяжья»/«говяжье» → «говяж», «свиной»/«свиная» → «свин».
  static String _stemToken(String token) {
    if (token.length <= 3) return token;
    if (token.length > 4 &&
        _fleeting.indexOf(token[token.length - 2]) >= 0 &&
        token.endsWith('к')) {
      return '${token.substring(0, token.length - 2)}к';
    }
    var res = token;
    while (res.length > 3 && _vowels.indexOf(res[res.length - 1]) >= 0) {
      res = res.substring(0, res.length - 1);
    }
    return res;
  }

  static const String _vowels = 'аеёиоуыэюяйь';
  static const String _fleeting = 'оеё';
}
