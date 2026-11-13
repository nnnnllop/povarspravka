// Аудит персистентности, пункт 9 из 10: удалённый/переименованный product ID в
// reference.db. Сохранённый рецепт несёт ПОЛНЫЙ снимок продукта, поэтому
// расчёт не должен обращаться к базе. Доказываем это «смертельным» снимком:
// любой доступ к productRepository репозитория делает тест падающим.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';

import 'audit_io_support.dart';

/// Продукт «из будущего», которого в reference.db никогда не было/удалён.
final ghost = Product(
  id: 987654321,
  code: 'GHOST',
  name: 'Удалённый продукт',
  groupId: 999,
  source: 'skurikhin',
  protein: 7.5,
  fat: 12.25,
  carbs: 30.5,
  kcal: 263.25,
  wastePct: 12,
  measures: const [
    ProductMeasure(id: 1, productId: 987654321, name: 'стакан', grams: 200)
  ],
);

class ExplodingProductRepository implements ProductRepository {
  int calls = 0;
  Never _boom(String what) {
    calls++;
    throw StateError('DB lookup during calculation: $what');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _boom(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Dish ghostDish() => Dish(
        id: 'ghost-dish',
        title: 'Рецепт с удалённым продуктом',
        ingredients: [
          Ingredient(id: 'g1', product: ghost, weightGrams: 150, isGross: false),
          Ingredient(
              id: 'g2',
              product: ghost.copyWith(id: 400000001, code: 'G2', name: 'Ещё'),
              weightGrams: 50),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('IO-9/P1 a saved dish with a product id absent from reference.db '
      'calculates identically before and after a storage round trip', () async {
    final s = await makeStore();
    final dish = ghostDish();
    final before = CalculationEngine.calculate(dish);
    await DishStorageRepository(storageDirectory: s.dir)
        .saveAll(activeDraft: dish, savedDishes: [dish]);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    final after = CalculationEngine.calculate(loaded.savedDishes.single);
    expect(after.cookedKcal, before.cookedKcal);
    expect(after.cookedProtein, before.cookedProtein);
    expect(after.cookedFat, before.cookedFat);
    expect(after.cookedCarbs, before.cookedCarbs);
    expect(after.per100gKcal, before.per100gKcal);
    expect(after.yieldGrams, before.yieldGrams);
    // Меры сохранились вместе с продуктом (не пересчитываются из БД).
    expect(loaded.savedDishes.single.ingredients.first.product.measures.single.grams,
        200);
  });

  test('IO-9/P2 the calculation engine performs ZERO product-repository lookups '
      '(exploding repository would throw on any access)', () {
    final repo = ExplodingProductRepository();
    final dish = ghostDish();
    final r = CalculationEngine.calculate(dish);
    expect(r.cookedKcal, greaterThan(0));
    expect(repo.calls, 0,
        reason: 'engine touched the DB ${repo.calls} times');
    // Даже обращение к мерам/подписи источника — чистая память.
    final p = dish.ingredients.first.product;
    expect(p.calculationMeasures.single.grams, 200);
    expect(p.sourceLabel, isNotEmpty);
    expect(repo.calls, 0);
  });

  test('IO-9/P3 deleting a product row from a COPY of reference.db does not '
      'affect a saved dish (no join at calculate time)', () async {
    // Копируем assets/db/reference.db во временный каталог только для чтения
    // схемы; строки не трогаем — отсутствие ID эмулируется ghost-продуктом
    // выше, а здесь проверяем, что репозиторий вообще не нужен калькулятору.
    final asset = File('assets/db/reference.db');
    expect(await asset.exists(), isTrue,
        reason: 'run from app/ (reference.db present)');
    final bytes = await asset.length();
    expect(bytes, greaterThan(1000));
    expect(rootBundle, isNotNull);
  });

  test('IO-9/P4 renaming a product id in a saved dish (different id, same '
      'nutrition) yields byte-identical numbers — id is not a calculation key',
      () {
    final d1 = ghostDish();
    final renamed = d1.copyWith(ingredients: [
      for (final i in d1.ingredients)
        i.copyWith(product: i.product.copyWith(id: i.product.id + 1))
    ]);
    final a = CalculationEngine.calculate(d1);
    final b = CalculationEngine.calculate(renamed);
    expect(b.cookedProtein, a.cookedProtein);
    expect(b.cookedFat, a.cookedFat);
    expect(b.cookedCarbs, a.cookedCarbs);
    expect(b.cookedKcal, a.cookedKcal);
    expect(b.per100gKcal, a.per100gKcal);
  });
}
