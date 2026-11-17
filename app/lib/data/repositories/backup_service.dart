import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/product.dart';

/// Разобранная резервная копия библиотеки рецептов и своих продуктов.
class ParsedBackup {
  final List<Dish> savedDishes;
  final List<Product> customProducts;
  final DateTime? exportedAt;

  const ParsedBackup({
    required this.savedDishes,
    required this.customProducts,
    this.exportedAt,
  });
}

/// Экспорт и импорт резервной копии библиотеки в переносимом JSON-формате.
class BackupService {
  static const String backupFormat = 'povarspravka-backup';
  static const int currentBackupVersion = 1;
  static const String appVersionLabel = '1.3.0';

  static String encodeBackup({
    required List<Dish> savedDishes,
    required List<Product> customProducts,
    DateTime? now,
  }) {
    final payload = <String, dynamic>{
      'format': backupFormat,
      'version': currentBackupVersion,
      'appVersion': appVersionLabel,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'savedDishes': [for (final d in savedDishes) d.toJson()],
      'customProducts': [for (final p in customProducts) p.toJson()],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
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
    final hasKnownKeys =
        decoded.containsKey('savedDishes') || decoded.containsKey('customProducts');
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

    final exportedAt =
        DateTime.tryParse(decoded['exportedAt'] as String? ?? '');
    return ParsedBackup(
      savedDishes: dishes,
      customProducts: customProducts,
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

  static Future<void> shareBackupFile({
    required List<Dish> savedDishes,
    required List<Product> customProducts,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final backupsRoot = Directory(p.join(tempDir.path, 'backups'));
    await backupsRoot.create(recursive: true);
    final stagingDir = await backupsRoot.createTemp('backup_');
    var handedOff = false;
    try {
      final fileName = backupFileName();
      final filePath = p.join(stagingDir.path, fileName);
      final file = File(filePath);
      final json = encodeBackup(
        savedDishes: savedDishes,
        customProducts: customProducts,
      );
      await file.writeAsString(json, flush: true);

      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'application/json', name: fileName)],
        subject: 'Резервная копия «Поварская справка»',
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
