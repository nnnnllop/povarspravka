import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/product.dart';

/// Разобранная резервная копия библиотеки рецептов, своих и избранных продуктов.
class ParsedBackup {
  final List<Dish> savedDishes;
  final List<Product> customProducts;
  final List<Product> favoriteProducts;
  final DateTime? exportedAt;

  const ParsedBackup({
    required this.savedDishes,
    required this.customProducts,
    this.favoriteProducts = const [],
    this.exportedAt,
  });
}

/// Экспорт и импорт резервной копии библиотеки и отдельных рецептов в JSON.
class BackupService {
  static const String backupFormat = 'povarspravka-backup';
  static const int currentBackupVersion = 1;
  static const String appVersionLabel = '1.7.0';

  static String encodeBackup({
    required List<Dish> savedDishes,
    required List<Product> customProducts,
    List<Product> favoriteProducts = const [],
    DateTime? now,
  }) {
    final payload = <String, dynamic>{
      'format': backupFormat,
      'version': currentBackupVersion,
      'appVersion': appVersionLabel,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'savedDishes': [for (final d in savedDishes) d.toJson()],
      'customProducts': [for (final item in customProducts) item.toJson()],
      if (favoriteProducts.isNotEmpty)
        'favoriteProducts': [for (final f in favoriteProducts) f.toJson()],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Формирует компактный переносимый JSON для одного блюда вместе с
  /// используемыми в нём «своими» продуктами (совместим с «Восстановить из копии»).
  static String encodeSingleDishBackup(
    Dish dish, {
    List<Product> customProducts = const [],
    DateTime? now,
  }) {
    final liveCustomById = <int, Product>{
      for (final prod in customProducts) prod.id: prod,
    };
    final referencedCustom = <Product>[];
    final seenIds = <int>{};
    for (final ing in dish.ingredients) {
      if (ing.product.source.trim().toLowerCase() == 'custom' &&
          seenIds.add(ing.product.id)) {
        referencedCustom.add(liveCustomById[ing.product.id] ?? ing.product);
      }
    }
    return encodeBackup(
      savedDishes: [dish],
      customProducts: referencedCustom,
      now: now,
    );
  }

  static ParsedBackup parseBackup(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Пустой текст резервной копии');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ожидался JSON-объект резервной копии');
    }
    final format = decoded['format'];
    final hasKnownKeys = decoded.containsKey('savedDishes') ||
        decoded.containsKey('customProducts') ||
        decoded.containsKey('favoriteProducts');
    if (format != null && format != backupFormat) {
      throw const FormatException('Неподдерживаемый формат резервной копии');
    }
    if (!hasKnownKeys) {
      throw const FormatException(
        'В файле нет данных рецептов или своих продуктов',
      );
    }

    final rawDishes = decoded['savedDishes'];
    if (rawDishes != null && rawDishes is! List) {
      throw const FormatException('Некорректный список блюд в резервной копии');
    }
    final dishes = <Dish>[];
    if (rawDishes is List) {
      for (final item in rawDishes) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Некорректная запись блюда');
        }
        dishes.add(Dish.fromJson(item));
      }
    }

    final rawCustom = decoded['customProducts'];
    if (rawCustom != null && rawCustom is! List) {
      throw const FormatException(
        'Некорректный список своих продуктов в резервной копии',
      );
    }
    final customProducts = <Product>[];
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Некорректная запись продукта');
        }
        final product = Product.fromJson(item);
        if (CalculationValidation.isValidProduct(product)) {
          customProducts.add(product.copyWith(source: 'custom'));
        }
      }
    }

    final rawFavorites = decoded['favoriteProducts'];
    if (rawFavorites != null && rawFavorites is! List) {
      throw const FormatException(
        'Некорректный список избранных продуктов в резервной копии',
      );
    }
    final favoriteProducts = <Product>[];
    if (rawFavorites is List) {
      final seenFavIds = <int>{};
      for (final item in rawFavorites) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Некорректная запись избранного продукта');
        }
        final product = Product.fromJson(item);
        if (seenFavIds.add(product.id) &&
            CalculationValidation.isValidProduct(product)) {
          favoriteProducts.add(product);
        }
      }
    }

    final exportedAt =
        DateTime.tryParse(decoded['exportedAt'] as String? ?? '');
    return ParsedBackup(
      savedDishes: dishes,
      customProducts: customProducts,
      favoriteProducts: favoriteProducts,
      exportedAt: exportedAt,
    );
  }

  static String backupFileName([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return 'povarspravka_backup_$y$m$d.json';
  }

  static String singleDishFileName(Dish dish) {
    final raw = dish.title.trim().isEmpty ? 'recipe' : dish.title.trim();
    final sanitized = raw
        .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final base = sanitized.isEmpty
        ? 'recipe'
        : (sanitized.length > 48 ? sanitized.substring(0, 48) : sanitized);
    return '${base}_recipe.json';
  }

  static Future<void> shareBackupFile({
    required List<Dish> savedDishes,
    required List<Product> customProducts,
    List<Product> favoriteProducts = const [],
  }) async {
    final json = encodeBackup(
      savedDishes: savedDishes,
      customProducts: customProducts,
      favoriteProducts: favoriteProducts,
    );
    await _shareJsonPayload(
      json: json,
      fileName: backupFileName(),
      subject: 'Резервная копия «Поварская справка»',
    );
  }

  static Future<void> shareSingleDishFile(
    Dish dish, {
    List<Product> customProducts = const [],
  }) async {
    final title =
        dish.title.trim().isEmpty ? 'Рецепт без названия' : dish.title.trim();
    final json = encodeSingleDishBackup(dish, customProducts: customProducts);
    await _shareJsonPayload(
      json: json,
      fileName: singleDishFileName(dish),
      subject: 'Рецепт «$title» — Поварская справка',
    );
  }

  static Future<void> _shareJsonPayload({
    required String json,
    required String fileName,
    required String subject,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final backupsRoot = Directory(p.join(tempDir.path, 'backups'));
    await backupsRoot.create(recursive: true);
    final stagingDir = await backupsRoot.createTemp('backup_');
    var handedOff = false;
    try {
      final filePath = p.join(stagingDir.path, fileName);
      final file = File(filePath);
      await file.writeAsString(json, flush: true);

      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'application/json', name: fileName)],
        subject: subject,
      );
      handedOff = true;
    } finally {
      if (!handedOff || defaultTargetPlatform == TargetPlatform.android) {
        try {
          await stagingDir.delete(recursive: true);
        } on FileSystemException {
          // best effort cleanup
        }
      }
    }
  }
}
