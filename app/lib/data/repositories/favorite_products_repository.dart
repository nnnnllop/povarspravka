import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/product.dart';

/// Локальное хранилище избранных продуктов («Базовая корзина») в
/// `favorite_products.json`.
class FavoriteProductsRepository {
  static const String _fileName = 'favorite_products.json';
  final Directory? storageDirectory;
  Future<void> _tail = Future<void>.value();

  FavoriteProductsRepository({this.storageDirectory});

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
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is! List) return const <Product>[];
          final seen = <int>{};
          final result = <Product>[];
          for (final item in decoded) {
            if (item is! Map<String, dynamic>) continue;
            try {
              final product = Product.fromJson(item);
              if (seen.add(product.id) &&
                  CalculationValidation.isValidProduct(product)) {
                result.add(product);
              }
            } catch (_) {
              // Пропускаем битую запись, сохраняя остальные избранные.
            }
          }
          return result;
        } catch (_) {
          return const <Product>[];
        }
      });

  Future<void> saveAll(List<Product> products) => _serialized(() async {
        final file = await _resolveFile();
        if (file == null) return;
        await file.parent.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        final payload = jsonEncode([for (final item in products) item.toJson()]);
        await tmp.writeAsString(payload, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path);
      });
}
