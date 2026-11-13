// Аудит персистентности, пункт 8 из 10: schema drift. Документ, записанный
// СТАРОЙ версией схемы (нет blankMode / showPer100gRowInExport / is_dish /
// measures / protein), должен загружаться с разумными умолчаниями, а продукт
// без явного белка — НЕ превращаться молча в 0 г белка.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

import 'audit_io_support.dart';

/// Документ «v0»: без blankMode, showPer100gRowInExport, is_dish, measures,
/// без protein у продукта.
Map<String, dynamic> ancientDishJson({bool dropProtein = true}) => {
      'id': 'ancient',
      'title': 'Старый рецепт',
      'ingredients': [
        {
          'id': 'ancient-1',
          'weightGrams': 100.0,
          'isGross': false,
          'product': {
            'id': 42,
            'code': '42',
            'name': 'Мука пшеничная',
            'group_id': 1,
            'source': 'skurikhin',
            'waste_pct': 0.0,
            if (!dropProtein) 'protein': 10.3,
            'fat': 1.1,
            'carbs': 69.5,
            'kcal': 334,
          },
        }
      ],
      'createdAt': '2023-01-01T00:00:00.000',
      'updatedAt': '2023-01-01T00:00:00.000',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-8/P1 ancient document (no blankMode, no showPer100gRowInExport, no '
      'is_dish, no measures) loads with graceful defaults', () async {
    final s = await makeStore();
    final ancient = ancientDishJson(dropProtein: false);
    await s.main.writeAsString(jsonEncode({
      'activeDraft': ancient,
      'savedDishes': [ancient],
    }), flush: true); // legacy: без storageVersion/crc32

    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    final d = loaded.savedDishes.single;
    expect(d.title, 'Старый рецепт');
    expect(d.blankMode.name, 'photoCross');
    expect(d.showPer100gRowInExport, isFalse);
    expect(d.showTitleInExport, isFalse);
    expect(d.retentionProtein, 0.94);
    expect(d.customYieldGrams, isNull);
    final p = d.ingredients.single.product;
    expect(p.measures, isEmpty);
    expect(p.isDish, isNull);
    expect(p.isDishOnly, isFalse);
    expect(p.hasExplicitProtein, isTrue);
    // И расчёт проходит.
    final r = CalculationEngine.calculate(d);
    expect(r.rawTotalProtein, greaterThan(0));
  });

  test('IO-8/P2 product WITHOUT explicit protein: hasExplicitProtein=false '
      'all the way from JSON through CalculationValidation and '
      'DishNotifier.addIngredient to calculate() — must NOT become 0 g',
      () async {
    final s = await makeStore();
    final ancient = ancientDishJson(); // protein key отсутствует
    await s.main.writeAsString(jsonEncode({
      'activeDraft': ancient,
      'savedDishes': [ancient],
    }), flush: true);

    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    // Ожидаемое: документ нельзя молча трактовать как «0 г белка» — он либо
    // отвергается с понятной ошибкой, либо загружается с явным маркером
    // отсутствия белка, но расчёт НЕ выдаёт 0 г.
    expect(err, isA<FormatException>(),
        reason: 'product without protein was accepted (error=$err)');

    // Прямой путь модели:
    final p = Product.fromJson({'id': 1, 'name': 'X'});
    expect(p.hasExplicitProtein, isFalse);
    expect(p.protein, 0);
    expect(() => CalculationValidation.product(p), throwsArgumentError);

    // Провайдер: addIngredient не даёт добавить такой продукт и не показывает
    // 0 г белка. Отказ тихий — пользовательские пути никогда не бросают.
    final notifier = DishNotifier();
    addTearDown(notifier.dispose);
    expect(() => notifier.addIngredient(p, 100), returnsNormally);
    expect(notifier.state.ingredients, isEmpty,
        reason: 'product without protein was added as 0 g protein');
  });

  test('IO-8/P3 a saved dish whose product lost its protein key (e.g. written '
      'by an old/новый dev build) does not calculate as 0 g protein', () {
    final p = Product.fromJson({
      'id': 1,
      'name': 'X',
      'fat': 1.0,
      'carbs': 1.0,
      'kcal': 10,
    });
    expect(p.hasExplicitProtein, isFalse);
    final dish = Dish(
        id: 'x',
        ingredients: [
          Ingredient(id: 'x1', product: p, weightGrams: 100)
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026));
    expect(() => CalculationEngine.calculate(dish), throwsArgumentError);
  });

  test('IO-8/P4 Product.toJson() omits protein when it is not explicit — the '
      'marker survives a save/load round trip', () async {
    final s = await makeStore();
    final explicit = Product.fromJson({
      'id': 1,
      'name': 'с белком',
      'protein': 5.0,
      'fat': 1.0,
      'carbs': 1.0,
      'kcal': 10,
    });
    final implicit = Product.fromJson({
      'id': 2,
      'name': 'без белка',
      'fat': 1.0,
      'carbs': 1.0,
      'kcal': 10,
    });
    expect(explicit.toJson().containsKey('protein'), isTrue);
    expect(implicit.toJson().containsKey('protein'), isFalse);
    final back = Product.fromJson(
        jsonDecode(jsonEncode(implicit.toJson())) as Map<String, dynamic>);
    expect(back.hasExplicitProtein, isFalse);
    expect(
        Product.fromJson(jsonDecode(jsonEncode(explicit.toJson()))
            as Map<String, dynamic>)
            .protein,
        5.0);
    // Через хранилище: явный белок не теряется.
    final d = Dish(
        id: 'p',
        ingredients: [
          Ingredient(id: 'i1', product: explicit, weightGrams: 100)
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026));
    await DishStorageRepository(storageDirectory: s.dir)
        .saveAll(activeDraft: d, savedDishes: [d]);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.single.ingredients.single.product.protein, 5.0);
    expect(
        loaded.savedDishes.single.ingredients.single.product.hasExplicitProtein,
        isTrue);
  });

  test('IO-8/P5 unknown blankMode name falls back to photoCross instead of '
      'crashing', () async {
    final s = await makeStore();
    final doc = ancientDishJson(dropProtein: false);
    doc['blankMode'] = 'ultraviolet';
    await s.main.writeAsString(jsonEncode({
      'activeDraft': doc,
      'savedDishes': [doc],
    }), flush: true);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.single.blankMode.name, 'photoCross');
  });

  test('IO-8/P6 wrong TYPE for a field (title: 5, ingredients: "x") is '
      'rejected, not silently coerced', () async {
    final s = await makeStore();
    final bad1 = ancientDishJson(dropProtein: false)..['title'] = 5;
    await s.main.writeAsString(jsonEncode({
      'activeDraft': bad1,
      'savedDishes': [bad1],
    }), flush: true);
    final err1 = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    expect(err1, isA<FormatException>());

    final s2 = await makeStore();
    final bad2 = ancientDishJson(dropProtein: false)
      ..['ingredients'] = 'not a list';
    await s2.main.writeAsString(jsonEncode({
      'activeDraft': bad2,
      'savedDishes': [bad2],
    }), flush: true);
    final err2 = await captureT(
        () => DishStorageRepository(storageDirectory: s2.dir).loadAll());
    expect(err2, isA<FormatException>());
  });

  test('IO-8/P7 storageVersion = 2 (future) is rejected as invalid and NOT '
      'treated as legacy (no silent downgrade of a newer library)', () async {
    final s = await makeStore();
    final doc = ancientDishJson(dropProtein: false);
    await s.main.writeAsString(jsonEncode({
      'storageVersion': 2,
      'crc32': 0,
      'activeDraft': doc,
      'savedDishes': [doc],
    }), flush: true);
    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    expect(err, isA<FormatException>());
  });
}
