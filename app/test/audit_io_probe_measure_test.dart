// Аудит персистентности, дополнительно (пункт 4 + 8): надёжность вычисляемых
// свойств, которые участвуют в расчёте уже ПОСЛЕ загрузки с диска.
// `Product.calculationMeasures` для Скурихина всегда вызывает
// `name.toLowerCase()` (product.dart:174–175) — сравнение имён мер.
// Dart `String.toLowerCase()` бросает исключение на непарном суррогате:
// такой title/product name МОЖЕТ попасть на диск через хранилище (round-trip
// Unicode PASSED), но последующий расчёт падает.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-4/P5 a lone surrogate in a MEASURE name survives storage and — '
      'contrary to the toLowerCase() hypothesis — does not break the '
      'calculation (Dart 3.5 lowercases lone surrogates without throwing)',
      () async {
    final s = await makeStore();
    final product = Product(
      id: 5,
      code: '5',
      name: 'Мука',
      groupId: 1,
      source: 'skurikhin',
      protein: 10,
      fat: 1,
      carbs: 70,
      kcal: 334,
      measures: const [
        ProductMeasure(id: 1, productId: 5, name: 'стакан \uD800', grams: 200),
      ],
    );
    final dish = Dish(
        id: 'd',
        ingredients: [Ingredient(id: 'i', product: product, weightGrams: 100)],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026));
    // Запись на диск проходит: lone surrogate кодируется как \ud800.
    await DishStorageRepository(storageDirectory: s.dir)
        .saveAll(activeDraft: dish, savedDishes: [dish]);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.single.ingredients.single.product.measures.single
        .name.codeUnits, 'стакан \uD800'.codeUnits);
    // toLowerCase() на непарном суррогате НЕ бросает (проверено Dart 3.5.4).
    expect((() => 'стакан \uD800'.toLowerCase()).call().codeUnits.isNotEmpty,
        isTrue);
    expect(() => CalculationEngine.calculate(loaded.savedDishes.single),
        returnsNormally);
    expect(product.calculationMeasures.single.grams, 200);
  });

  test('IO-4/P6 well-formed product names in measures do not throw', () {
    final product = Product(
      id: 5,
      code: '5',
      name: 'Мука',
      groupId: 1,
      source: 'skurikhin',
      protein: 10,
      fat: 1,
      carbs: 70,
      kcal: 334,
      measures: const [
        ProductMeasure(id: 1, productId: 5, name: 'Стакан 250 мл', grams: 200),
      ],
    );
    expect(product.calculationMeasures.single.grams, 200);
  });
}
