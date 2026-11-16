import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/product.dart';

/// Локальное хранилище пользовательских («своих») продуктов в JSON.
///
/// Эталонная база `assets/db/reference.db` остаётся строго read-only;
/// пользовательские продукты хранятся отдельно, получают отрицательные ID
/// (`<= -1000`), чтобы не пересекаться с записями справочника, и целиком
/// сериализуются внутри сохранённых блюд.
class CustomProductsRepository {
  static const String _fileName = 'custom_products.json';
  static const int _firstCustomId = -1000;

  final Directory? storageDirectory;
  Future<void> _tail = Future<void>.value();

  CustomProductsRepository({this.storageDirectory});

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

  Future<List<Product>> loadAll() => _serialized(() async {
        final file = await _resolveFile();
        if (file == null || !await file.exists()) {
          return const <Product>[];
        }
        try {
          final raw = await file.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is! List) return const <Product>[];
          final items = <Product>[];
          for (final entry in decoded) {
            if (entry is Map<String, dynamic>) {
              final product = Product.fromJson(entry);
              if (CalculationValidation.isValidProduct(product)) {
                items.add(product);
              }
            }
          }
          return items;
        } catch (_) {
          // Повреждённый пользовательский файл не должен блокировать поиск.
          return const <Product>[];
        }
      });

  Future<void> saveAll(List<Product> products) => _serialized(() async {
        final file = await _resolveFile();
        if (file == null) return;
        await file.parent.create(recursive: true);
        final payload = jsonEncode([
          for (final product in products) product.toJson(),
        ]);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(payload, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path);
      });

  /// Вычисляет следующий свободный отрицательный ID для нового продукта.
  static int nextId(Iterable<Product> existing) {
    var minId = _firstCustomId + 1;
    for (final p in existing) {
      if (p.id < minId) minId = p.id;
    }
    final candidate = minId - 1;
    return candidate <= _firstCustomId ? candidate : _firstCustomId;
  }

  static String normalizeText(String input) => input
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
