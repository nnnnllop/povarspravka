// Shared fixtures for the state / provider / UI-logic re-audit.
//
// Everything here is test-only. It never touches `lib/`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart'
    show SourceCounts, sourceCountsProvider;

/// A nested `ProviderScope` that overrides ONLY the search stack, so the
/// dish providers stay bound to the outer scope (where the harness overrides
/// live) while the product repository is a test double.
Widget newSearchScope(ProductRepository repo, Widget child) => ProviderScope(
      overrides: [
        productRepositoryProvider.overrideWithValue(repo),
        searchProvider.overrideWith((ref) => SearchNotifier(repo)),
        sourceCountsProvider.overrideWith((ref) async => const SourceCounts()),
      ],
      child: child,
    );

// ── Products ────────────────────────────────────────────────────────────────

const beet = Product(
  id: 9002,
  code: 'b',
  name: 'Свекла',
  groupId: 1,
  source: 'skurikhin',
  protein: 1.5,
  fat: .1,
  carbs: 8.8,
  kcal: 42,
);

const butter = Product(
  id: 9001,
  code: 'f',
  name: 'Масло сливочное',
  groupId: 1,
  source: 'skurikhin',
  protein: 0,
  fat: 99.9,
  carbs: 0,
  kcal: 899,
);

const potato = Product(
  id: 9003,
  code: 'p',
  name: 'Картофель',
  groupId: 5,
  source: 'skurikhin',
  wastePct: 25,
  protein: 2,
  fat: 0.4,
  carbs: 16.1,
  kcal: 77,
);

const buckwheat = Product(
  id: 9004,
  code: 'g',
  name: 'Крупа гречневая',
  groupId: 7,
  source: 'skurikhin',
  protein: 12.6,
  fat: 3.3,
  carbs: 62.1,
  kcal: 329,
);

/// A product whose macro sum exceeds 100 g — the BLS corruption class.
const corruptProduct = Product(
  id: 9005,
  code: 'x',
  name: 'Битый продукт BLS',
  groupId: 101,
  source: 'bls',
  protein: 60,
  fat: 60,
  carbs: 60,
  kcal: 400,
);

// ── Dishes ──────────────────────────────────────────────────────────────────

Dish dishWith(List<Ingredient> ings,
        {String id = 'd1',
        String title = 'Тест',
        double? customYield,
        double? retentionP,
        double? retentionF,
        double? retentionC}) =>
    Dish(
      id: id,
      title: title,
      ingredients: ings,
      customYieldGrams: customYield,
      retentionProtein: retentionP ?? 0.94,
      retentionFat: retentionF ?? 0.88,
      retentionCarbs: retentionC ?? 0.91,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Valid data, but the dish-level yield is sub-1 g → `CalculationEngine`
/// throws (MATH-05), so `tryCalculate` returns null.
Dish uncalculableDish({String id = 'bad', String title = 'Невычислимое'}) =>
    dishWith(
      const [Ingredient(id: 'i-1', product: butter, weightGrams: 600)],
      id: id,
      title: title,
      customYield: 0.1,
    );

Dish healthyDish({String id = 'ok', String title = 'Свекла отварная'}) =>
    dishWith(
      const [Ingredient(id: 'i-1', product: beet, weightGrams: 200)],
      id: id,
      title: title,
    );

// ── Storage doubles ─────────────────────────────────────────────────────────

/// Records every write; no IO.
class RecordingStorage extends DishStorageRepository {
  RecordingStorage({this.initial});

  final DishStorageData? initial;
  final List<Dish?> drafts = [];
  List<Dish> saved = const [];

  Dish? get lastDraft => drafts.isEmpty ? null : drafts.last;

  @override
  Future<DishStorageData> loadAll() async => initial ?? const DishStorageData();

  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {
    drafts.add(activeDraft);
    saved = List<Dish>.from(savedDishes);
  }
}

/// `loadAll()` blocks until [releaseLoad] — used to stage "edit before load
/// completes" (STATE-06a/06b).
class SlowLoadStorage extends DishStorageRepository {
  SlowLoadStorage({required this.stored, this.delayLoad = true});

  final Dish? stored;
  bool delayLoad;
  final _gate = Completer<void>();
  final writes = <Dish?>[];

  void releaseLoad() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<DishStorageData> loadAll() async {
    if (delayLoad) await _gate.future;
    return DishStorageData(
        activeDraft: stored, savedDishes: const <Dish>[]);
  }

  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {
    writes.add(activeDraft);
  }
}

/// Storage that never finishes loading.
class HungStorage extends DishStorageRepository {
  int saveCalls = 0;
  @override
  Future<DishStorageData> loadAll() => Completer<DishStorageData>().future;
  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {
    saveCalls++;
  }
}

/// Product repository double: returns a fixed list, optionally after [delay].
class FakeProductRepo extends ProductRepository {
  FakeProductRepo({this.results = const [beet, potato, butter], this.delay});

  final List<Product> results;
  Duration? delay;
  final queries = <String>[];

  @override
  Future<List<Product>> searchProducts(
      {required String query,
      int? groupId,
      String? source,
      bool? isDish,
      int limit = 50}) async {
    queries.add(query);
    if (delay != null) await Future<void>.delayed(delay!);
    return results
        .where((p) => query.trim().isEmpty
            ? true
            : p.name.toLowerCase().contains(query.trim().toLowerCase()))
        .toList();
  }

  @override
  Future<Map<String, int>> getCountBySource({bool? isDish}) async =>
      const {'skurikhin': 3, 'bls': 1};

  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => const [];

  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async =>
      const [];
}

// ── App harness ─────────────────────────────────────────────────────────────

class Harness {
  Harness({
    DishNotifier? dish,
    SavedDishesNotifier? saved,
    ProductRepository? repo,
  })  : dishNotifier = dish ?? DishNotifier(storage: RecordingStorage()),
        savedNotifier = saved,
        productRepo = repo ?? FakeProductRepo();

  final DishNotifier dishNotifier;
  final SavedDishesNotifier? savedNotifier;
  final ProductRepository productRepo;

  Widget wrap(Widget home) => ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => dishNotifier),
          if (savedNotifier != null)
            savedDishesProvider.overrideWith((ref) => savedNotifier!),
          productRepositoryProvider.overrideWithValue(productRepo),
        ],
        child: newSearchScope(
          productRepo,
          MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('ru', 'RU'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
            home: home,
          ),
        ),
      );

  void dispose() {
    // Riverpod disposes the overridden notifier itself when the ProviderScope
    // unmounts; disposing here as well would double-dispose it.
  }
}

/// Puts the whole test surface at a phone-sized logical window.
void phoneSize(WidgetTester tester,
    {Size size = const Size(390, 844), double dpr = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// All text rendered inside the current tree, concatenated — lets a test
/// assert "what the user actually sees" without knowing the widget layout.
String visibleText(WidgetTester tester) {
  final buf = StringBuffer();
  for (final w in tester.allWidgets) {
    if (w is Text) {
      final s = w.data ?? w.textSpan?.toPlainText();
      if (s != null && s.isNotEmpty) buf.writeln(s);
    }
  }
  return buf.toString();
}
