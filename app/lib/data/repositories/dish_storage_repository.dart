import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/calculation_validation.dart';

class DishStorageData {
  final Dish? activeDraft;
  final List<Dish> savedDishes;

  const DishStorageData({this.activeDraft, this.savedDishes = const []});
}

class DishStorageRepository {
  static const String _fileName = 'povarspravka_user_dishes.json';
  final Directory? storageDirectory;
  Map<String, dynamic>? _memoryFallback;
  Future<void> _tail = Future<void>.value();

  DishStorageRepository({this.storageDirectory});

  // One queue covers every writer (draft and library) and recovery reads.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<File?> _getStorageFile() async {
    if (storageDirectory != null) {
      return File(p.join(storageDirectory!.path, _fileName));
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File(p.join(dir.path, _fileName));
    } on MissingPluginException {
      // Unsupported plugin hosts may use memory; real I/O failures must surface.
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  DishStorageData _decode(Map<String, dynamic> raw) {
    if (!raw.containsKey('activeDraft') ||
        raw['savedDishes'] is! List ||
        (raw['activeDraft'] != null &&
            raw['activeDraft'] is! Map<String, dynamic>)) {
      throw const FormatException('Invalid dishes document');
    }
    final saved = <Dish>[];
    final dishIds = <String>{};
    for (final item in raw['savedDishes'] as List) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved dish');
      }
      final decoded = _decodeDish(item);
      if (dishIds.contains(decoded.id)) {
        throw const FormatException('Duplicate dish ID in saved dishes');
      }
      dishIds.add(decoded.id);
      saved.add(decoded);
    }
    return DishStorageData(
      activeDraft: raw['activeDraft'] == null
          ? null
          : _decodeDish(raw['activeDraft'] as Map<String, dynamic>),
      savedDishes: saved,
    );
  }

  Dish _decodeDish(Map<String, dynamic> raw) {
    if (raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        raw['ingredients'] is! List) {
      throw const FormatException('Invalid dish structure');
    }
    for (final item in raw['ingredients'] as List) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          item['weightGrams'] is! num ||
          !(item['weightGrams'] as num).toDouble().isFinite ||
          (item['weightGrams'] as num).toDouble() <= 0 ||
          item['product'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid ingredient structure');
      }
    }
    final dish = Dish.fromJson(raw);
    try {
      CalculationValidation.dish(dish);
    } on ArgumentError {
      throw const FormatException('Invalid calculation values in dish');
    }
    final ids = dish.ingredients.map((i) => i.id).toSet();
    if (ids.contains('') || ids.length != dish.ingredients.length) {
      throw const FormatException('Missing or duplicate ingredient ID');
    }
    return dish;
  }

  Future<Map<String, dynamic>?> _readValid(File file) async {
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final raw = jsonDecode(text);
      if (raw is! Map<String, dynamic>) return null;
      _decode(raw); // Validate the complete payload, not just its JSON syntax.
      return raw;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<DishStorageData> loadAll() => _serialized(() async {
        final file = await _getStorageFile();
        if (file == null) {
          return _memoryFallback == null
              ? const DishStorageData()
              : _decode(_memoryFallback!);
        }
        var raw = await _readValid(file);
        if (raw == null) {
          final backup = File('${file.path}.bak');
          raw = await _readValid(backup);
          if (raw != null) {
            final temp = File('${file.path}.tmp');
            await temp.writeAsString(jsonEncode(raw), flush: true);
            // Never replace the good backup with the damaged main document.
            await temp.rename(file.path);
          } else if (await file.exists() || await backup.exists()) {
            throw const FormatException(
                'Main dishes document and backup are invalid');
          }
        }
        if (raw == null) return const DishStorageData();
        _memoryFallback = raw;
        return _decode(raw);
      });

  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) {
    // Serialize immediately, so mutations after this call cannot alter its snapshot.
    final payload = <String, dynamic>{
      'activeDraft': activeDraft?.toJson(),
      'savedDishes': savedDishes.map((d) => d.toJson()).toList(),
    };
    _decode(payload);
    final encoded = jsonEncode(payload);
    return _serialized(() async {
      final file = await _getStorageFile();
      if (file == null) {
        _memoryFallback = payload;
        return;
      }
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      final previous = await _readValid(file);
      if (previous != null) {
        final backupTemp = File('${file.path}.bak.tmp');
        await backupTemp.writeAsBytes(await file.readAsBytes(), flush: true);
        await backupTemp.rename('${file.path}.bak');
      }
      // Same-directory rename replaces the destination; no delete/write gap.
      await temp.rename(file.path);
      _memoryFallback = payload;
    });
  }
}
