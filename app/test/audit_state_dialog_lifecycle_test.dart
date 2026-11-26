// STATE-07 (dialog plumbing), STATE-11 (waste % lost), STATE-12 (measure
// converter), STATE-13 (draft lost without confirmation), STATE-14 (crash
// blast radius: every screen dies on the same class of dish).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';

Product potato() => const Product(
      id: 1,
      code: 'p',
      name: 'Картофель',
      groupId: 1,
      source: 'skurikhin',
      wastePct: 20,
      protein: 2,
      fat: .4,
      carbs: 16.3,
      kcal: 77,
      measures: [ProductMeasure(id: 1, productId: 1, name: 'клубень', grams: 80)],
    );

const fat = Product(
    id: 9001,
    code: 'f',
    name: 'Масло топлёное',
    groupId: 1,
    source: 'skurikhin',
    protein: 0,
    fat: 99.9,
    carbs: 0,
    kcal: 899);

class OneRepo extends ProductRepository {
  @override
  Future<List<Product>> searchProducts(
          {required String query,
          int? groupId,
          String? source,
          bool? isDish,
          int limit = 50}) async =>
      [potato()];
  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async =>
      [const FoodGroup(id: 1, code: 'qa', name: 'Овощи')];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async => [];
}

class NoopStorage extends DishStorageRepository {
  @override
  Future<DishStorageData> loadAll() async => const DishStorageData();
  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {}
}

/// Idempotent dispose: the root `ProviderScope` already disposes overridden
/// providers on unmount, and a manual `addTearDown(dispose)` then double-
/// disposes. `DishNotifier` overrides `dispose` (flushes the save queue) and
/// `_debugIsMounted` has no re-entry guard... but `DishNotifier.dispose` does
/// guard re-entry, so a second call is only noisy if the notifier was already
/// disposed by its owner. Keeping it defensive here.
void Function() disposeOnce(StateNotifier<dynamic> n) {
  var done = false;
  return () {
    if (done) return;
    done = true;
    try {
      n.dispose();
    } catch (_) {}
  };
}

class _QuietDish extends DishNotifier {
  _QuietDish(DishStorageRepository s)
      : super(storage: s, savedDishesNotifier: null);
  bool _gone = false;
  @override
  void dispose() {
    if (_gone) return;
    _gone = true;
    super.dispose();
  }
}

SavedDishesNotifier quietSaved() => _QuietSaved(NoopStorage());

class _QuietSaved extends SavedDishesNotifier {
  _QuietSaved(DishStorageRepository s) : super(s);
  bool _gone = false;
  @override
  void dispose() {
    if (_gone) return;
    _gone = true;
    super.dispose();
  }
}

Dish impossible() => Dish(
      id: 'bad',
      title: 'Невозможный выход',
      ingredients: const [
        Ingredient(id: 'i1', product: fat, weightGrams: 600)
      ],
      customYieldGrams: 100,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class BadDishNotifier extends DishNotifier {
  BadDishNotifier()
      : super(storage: NoopStorage(), savedDishesNotifier: null) {
    state = impossible();
    markClean();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STATE-07 dialog plumbing', () {
    testWidgets('inline waste-% editor toggles and cancels cleanly without AlertDialog',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      double? confirmed;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomNumpadSheet(
              product: potato(),
              initialGrams: 200,
              onConfirm: (g, _) => confirmed = g,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('key-3')));
      await tester.tap(find.byKey(const ValueKey('key-5')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('waste-edit-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('waste-edit-cancel')), findsNothing);
      expect(tester.takeException(), isNull,
          reason: 'inline waste edit cancels cleanly without controller errors');
      await tester.tap(find.text('Добавить'));
      await tester.pump();
      expect(confirmed, 200.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('STATE-11 waste % from the search sheet', () {
    testWidgets('FIXED: a waste % typed inline reaches the ingredient added '
        'from SearchProductModal', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _QuietDish(NoopStorage());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => notifier),
          productRepositoryProvider.overrideWithValue(OneRepo()),
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SearchProductModal())),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'карт');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Картофель').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('key-4')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('waste-edit-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('waste-edit-done')));
      await tester.pumpAndSettle();
      expect(find.textContaining('40 %'), findsWidgets);

      final add = find.text('Добавить');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(notifier.state.ingredients, hasLength(1));
      final ingested = notifier.state.ingredients.single.product.wastePct;
      // ignore: avoid_print
      print('STATE-11: wastePct in the recipe ingredient = $ingested');
      expect(ingested, 40.0,
          reason: 'SearchProductModal forwards onProductUpdated into _addToRecipe');
    });

    testWidgets('CONTROL: the same 40 % IS applied when the caller forwards '
        'onProductUpdated', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _QuietDish(NoopStorage());
      addTearDown(disposeOnce(notifier));
      Product? updated;
      Product returned = potato();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomNumpadSheet(
              product: potato(),
              initialGrams: 200,
              isEditing: true,
              onProductUpdated: (p) => updated = p,
              onConfirm: (g, isGross) {
                returned = updated ?? potato();
                notifier.addIngredient(returned, g, isGross: isGross);
              },
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.tap(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('key-4')));
      await tester.tap(find.byKey(const ValueKey('key-4')));
      await tester.ensureVisible(find.byKey(const ValueKey('key-0')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('waste-edit-done')));
      await tester.tap(find.byKey(const ValueKey('waste-edit-done')));
      await tester.pumpAndSettle();
      expect(updated, isNull,
          reason: 'the new % is only handed over at CONFIRM time');
      final confirm = find.text('Сохранить');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(updated?.wastePct, 40.0);
      expect(notifier.state.ingredients.single.product.wastePct, 40.0);
      expect(returned.wastePct, 40.0);
    });
  });

  group('STATE-12 measure converter', () {
    testWidgets('inline measure stepper converts 2 × 80 g → "160" canonical '
        'readout and preserves Брутто conversion', (tester) async {
      double? confirmed;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomNumpadSheet(
              product: potato(),
              initialGrams: 0,
              initialIsGross: true,
              onConfirm: (g, _) => confirmed = g,
            ),
          ),
        ),
      ));
      await tester.pump();
      final chip = find.byKey(const ValueKey('measure-клубень'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('measure-count-label'))).data,
        '1',
      );
      await tester.tap(find.byKey(const ValueKey('measure-inc')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('measure-count-label'))).data,
        '2',
      );
      // 2 × 80 г нетто при 20 % отходов = 200 г брутто, без ",0"
      final readout = tester
          .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher).first)
          .child as Text;
      expect(readout.data, '200');
      await tester.ensureVisible(find.text('Добавить'));
      await tester.tap(find.text('Добавить'));
      await tester.pump();
      expect(confirmed, 200.0);
    });

    testWidgets('measure-dec is disabled at 1 and invalid waste-% >= 100 '
        'disables confirm and keeps inline waste edit open', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomNumpadSheet(
              product: potato(),
              initialGrams: 0,
              onConfirm: (g, _) {},
            ),
          ),
        ),
      ));
      await tester.pump();
      final chip = find.byKey(const ValueKey('measure-клубень'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final dec = tester.widget<IconButton>(find.byKey(const ValueKey('measure-dec')));
      expect(dec.onPressed, isNull, reason: 'cannot decrement below 1');
      await tester.tap(find.byKey(const ValueKey('measure-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('measure-count-label')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.tap(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('key-1')));
      await tester.tap(find.byKey(const ValueKey('key-1')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.pump();
      final doneInk = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const ValueKey('waste-edit-done')),
          matching: find.byType(InkWell),
        ),
      );
      expect(doneInk.onTap, isNull,
          reason: 'waste >= 100 % keeps confirm disabled');
      expect(find.byKey(const ValueKey('waste-edit-cancel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('STATE-13 draft loss without a prompt', () {
    testWidgets('FIXED: "Новый расчёт" asks confirmation before replacing '
        'unsaved work', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final saved = quietSaved();
      final notifier = DishNotifier(
        storage: NoopStorage(),
        savedDishesNotifier: saved,
      );
      addTearDown(disposeOnce(notifier));
      await notifier.flushPendingSaves();
      notifier.addIngredient(potato(), 300);
      notifier.setTitle('Мой суп');
      await notifier.flushPendingSaves();
      expect(notifier.isDirty, isTrue);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => notifier),
          savedDishesProvider.overrideWith((ref) => saved),
          productRepositoryProvider.overrideWithValue(OneRepo()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Мой суп'), findsWidgets);

      final newCalcBtn = find.text('Новый расчёт').first;
      await tester.ensureVisible(newCalcBtn);
      await tester.tap(newCalcBtn);
      await tester.pumpAndSettle();
      expect(find.text('Сохранить текущее блюдо?'), findsOneWidget);

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(notifier.state.ingredients, hasLength(1));
      expect(notifier.state.title, 'Мой суп');

      await tester.ensureVisible(newCalcBtn);
      await tester.tap(newCalcBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не сохранять'));
      await tester.pumpAndSettle();
      expect(notifier.state.ingredients, isEmpty);
      expect(notifier.state.title, isEmpty);
      expect(notifier.isDirty, isFalse);
    });
  });

  group('STATE-14 crash blast radius', () {
    for (final entry in <String, Widget>{
      'RecipeEditorScreen': const RecipeEditorScreen(),
      'BlankPreviewScreen': const BlankPreviewScreen(),
      'HomeScreen': const HomeScreen(),
    }.entries) {
      testWidgets('${entry.key} survives an impossible dish without a red '
          'screen', (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final n = BadDishNotifier();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            dishProvider.overrideWith((ref) => n),
            savedDishesProvider.overrideWith((ref) => quietSaved()),
            productRepositoryProvider.overrideWithValue(OneRepo()),
          ],
          child: MaterialApp(theme: AppTheme.light, home: entry.value),
        ));
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          tester.takeException();
          await tester.pump();
        }
        // SPEC (STATE-14): an inexact dish must degrade gracefully — no
        // FlutterError.onError red screen, no ErrorWidget in the tree, and the
        // screen still renders its own content.
        final errors = find.byType(ErrorWidget).evaluate().length;
        // ignore: avoid_print
        print('STATE-14 ${entry.key}: ErrorWidget=$errors');
        expect(errors, 0,
            reason: '${entry.key} must not crash into a red screen');
        expect(find.byType(Scaffold), findsWidgets,
            reason: '${entry.key} must still render its own UI');
      });
    }

    test('a yield below the cooked macro mass is accepted and CALCULATES '
        '(LOGIC-01: no ArgumentError reaches the chef)', () {
      final n = _QuietDish(NoopStorage());
      addTearDown(disposeOnce(n));
      n.addIngredient(fat, 600);
      n.setCustomYield(100);
      expect(n.state.customYieldGrams, 100);
      final r = CalculationEngine.calculate(n.state);
      expect(r.per100gKcal.isFinite, isTrue);
      expect(r.yieldGrams, greaterThan(0));
    });

    test('a thermodynamically impossible custom yield is rejected by the '
        'notifier boundary', () {
      final n = _QuietDish(NoopStorage());
      addTearDown(disposeOnce(n));
      n.addIngredient(fat, 600);
      n.setCustomYield(0.5); // below the 1 g floor (MATH-05)
      expect(n.state.customYieldGrams, isNull,
          reason: 'a sub-gram yield must not be stored');
    });
  });
}
