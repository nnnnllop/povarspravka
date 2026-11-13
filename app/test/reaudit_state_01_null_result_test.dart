// REAUDIT item 1 + 2 — `tryCalculate` / `calculationResultProvider` === null.
//
// Every use site of the nullable result is enumerated and the *actual*
// user-visible rendering is asserted (rendered tree, not source text).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/calc_error_banner.dart';

import 'reaudit_state_support.dart';

/// Dishes whose data FAIL `CalculationEngine.calculate`.
class BadDish {
  static Dish subGramYield() => uncalculableDish();

  /// `retention = 0` — only reachable from *stored* JSON: the notifier's
  /// `setRetention` refuses 0, but `Dish.fromJson` accepts whatever it reads.
  static Dish zeroRetention() => dishWith(
        const [Ingredient(id: 'i', product: butter, weightGrams: 1000)],
        id: 'zr',
        title: 'Нулевая сохранность',
        retentionP: 0,
        retentionF: 0,
        retentionC: 0,
      );

  /// `wastePct = 100` — only reachable from stored JSON (UI clamps 0…99).
  static Dish waste100() => dishWith(
        const [
          Ingredient(
              id: 'i',
              product: Product(
                id: 9100,
                code: 'w',
                name: 'Отходы 100',
                groupId: 1,
                source: 'skurikhin',
                wastePct: 100,
                protein: 2,
                fat: 0,
                carbs: 10,
                kcal: 48,
              ),
              weightGrams: 200,
              isGross: true),
        ],
        id: 'w100',
        title: 'Отходы 100%',
      );

  static Dish outOfRangeYield() => dishWith(
        const [Ingredient(id: 'i', product: beet, weightGrams: 200)],
        id: 'cy',
        title: 'Выход вне диапазона',
        customYield: 0.5,
      );
}

Harness editorHarness(Dish dish) {
  final n = DishNotifier(storage: RecordingStorage());
  n.loadDish(dish);
  return Harness(dish: n);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('enumeration: the five inputs that really produce a null result', () {
    test('sub-1 g customYield', () {
      expect(CalculationEngine.tryCalculate(BadDish.subGramYield()), isNull);
    });
    test('retention = 0 (stored document)', () {
      expect(CalculationEngine.tryCalculate(BadDish.zeroRetention()), isNull);
    });
    test('wastePct = 100 (stored document)', () {
      expect(CalculationEngine.tryCalculate(BadDish.waste100()), isNull);
    });
    test('customYield below the 1 g floor', () {
      expect(
          CalculationEngine.tryCalculate(BadDish.outOfRangeYield()), isNull);
    });
    test('product with P+F+C > 100', () {
      final d = dishWith(
          const [Ingredient(id: 'i', product: corruptProduct, weightGrams: 100)],
          id: 'c');
      expect(CalculationEngine.tryCalculate(d), isNull);
    });
    test('the interactive UI cannot produce these values', () {
      final n = DishNotifier(storage: RecordingStorage());
      n.addIngredient(butter, 600);
      n.setCustomYield(0.1);
      expect(n.state.customYieldGrams, isNull);
      n.setRetention(protein: 0, fat: 0, carbs: 0);
      expect(n.state.retentionProtein, 0.94);
      final before = n.state.ingredients.length;
      n.addIngredient(corruptProduct, 100);
      expect(n.state.ingredients.length, before);
      n.dispose();
    });
  });

  // ── The "serious defect" question: does a null silently render zeros? ─────
  group('NULL IS NOT SILENT ZERO (control) — but it IS silent on HOME', () {
    testWidgets('editor: dashes, never a plausible 0', (tester) async {
      phoneSize(tester);
      final h = editorHarness(BadDish.subGramYield());
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      expect(find.text('После т.о. · — Б — Ж — У — ккал'), findsOneWidget);
      expect(find.textContaining('0,00 ккал'), findsNothing);
    });

    testWidgets('editor stays editable while the calculation is null',
        (tester) async {
      phoneSize(tester);
      final h = editorHarness(BadDish.subGramYield());
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Название блюда'), 'Новое имя');
      await tester.pump();
      final ctx = tester.element(find.byType(RecipeEditorScreen));
      final c = ProviderScope.containerOf(ctx, listen: false);
      expect(c.read(dishProvider).title, 'Новое имя');
      expect(c.read(calculationResultProvider), isNull);
      expect(find.text('Ингредиенты · 1'), findsOneWidget);
    });

    testWidgets(
        'HOME-1: the active-draft card renders "выход — г · — ккал" with '
        'NO banner and NO reason', (tester) async {
      phoneSize(tester);
      final n = DishNotifier(storage: RecordingStorage());
      n.loadDish(BadDish.zeroRetention());
      final saved = SavedDishesNotifier(RecordingStorage());
      saved.setInitialDishes(const [], null);
      final h = Harness(dish: n, saved: saved);
      await tester.pumpWidget(h.wrap(const HomeScreen()));
      await tester.pump();
      expect(find.text('1 инг. · выход — г · — ккал'), findsOneWidget);
      expect(find.byType(CalcErrorBanner), findsNothing);
      expect(find.textContaining('Проверьте'), findsNothing);
    });

    testWidgets(
        'HOME-2: a SAVED dish with the same defect also degrades to dashes '
        'silently', (tester) async {
      phoneSize(tester);
      final n = DishNotifier(storage: RecordingStorage());
      n.loadDish(healthyDish());
      final saved = SavedDishesNotifier(RecordingStorage());
      saved.setInitialDishes([BadDish.zeroRetention()], null);
      final h = Harness(dish: n, saved: saved);
      await tester.pumpWidget(h.wrap(const HomeScreen()));
      await tester.pump();
      expect(find.text('Нулевая сохранность'), findsOneWidget);
      expect(find.text('1 инг. · выход — г · — ккал'), findsOneWidget);
      expect(find.byType(CalcErrorBanner), findsNothing);
    });
  });

  // ── Editor banner: placement and message quality ─────────────────────────
  group('EDITOR banner', () {
    testWidgets('present for sub-1 g yield', (tester) async {
      phoneSize(tester);
      final h = editorHarness(BadDish.subGramYield());
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Проверьте выход и параметры блюда'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('message is the raw validator range, not actionable text',
        (tester) async {
      phoneSize(tester);
      final h = editorHarness(BadDish.subGramYield());
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      final t = visibleText(tester);
      expect(t, contains('Проверьте выход и параметры блюда'));
      expect(t, contains('Expected finite 1.0..9999999.0'),
          reason: 'the second line is the English ArgumentError text');
      expect(t, isNot(contains('customYieldGrams')));
    });

    testWidgets('message names the wrong culprit for an ingredient defect',
        (tester) async {
      phoneSize(tester);
      final h = editorHarness(BadDish.zeroRetention());
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      final t = visibleText(tester);
      expect(t, contains('Проверьте выход и параметры блюда'));
      expect(t, contains('Expected finite 0.01..1.0'));
      // Переписано: название блюда законно видно в заголовке редактора и
      // поле «Название», поэтому проверяем только текст самого баннера:
      // он не называет виновника (нулевую сохранность legacy-документа).
      final banner = find.byType(CalcErrorBanner);
      expect(banner, findsOneWidget);
      expect(
          find.descendant(of: banner, matching: find.textContaining('Сохранность 0')),
          findsNothing);
      expect(
          find.descendant(
              of: banner, matching: find.textContaining('Нулевая сохранность')),
          findsNothing);
    });

    testWidgets('message for waste=100 says "check yield", cause is dry-matter '
        'rounding', (tester) async {
      phoneSize(tester);
      final h = editorHarness(BadDish.waste100());
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      final t = visibleText(tester);
      expect(t, contains('Expected finite 0.0..99.999'));
    });

    // Переписано (миссия «только нутриенты после т.о.»): дефект устранён —
    // баннер ошибки расчёта не уезжает вместе со списком. Тест теперь
    // закрепляет исправленное поведение вместо дефектного.
    testWidgets(
        'FIXED: scrolling the ingredient list keeps the error banner visible',
        (tester) async {
      phoneSize(tester, size: const Size(390, 520));
      final h = editorHarness(dishWith(
        [
          for (var i = 0; i < 12; i++)
            Ingredient(
                id: 'i$i', product: beet, weightGrams: 100 + i.toDouble()),
        ],
        id: 'scroll',
        title: 'Длинное блюдо',
        customYield: 0.1,
      ));
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      expect(find.byType(CalcErrorBanner), findsOneWidget);

      await tester.drag(find.byType(ReorderableListView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.byType(CalcErrorBanner), findsOneWidget,
          reason: 'the banner is pinned outside the scrolling list');
      expect(find.text('После т.о. · — Б — Ж — У — ккал'), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
    });
  });

  // ── D_shown_fail: banner itself cannot be laid out inside the blank ─────
  group('BLANK banner', () {
    testWidgets('healthy dish renders fine (control)', (tester) async {
      phoneSize(tester);
      final n = DishNotifier(storage: RecordingStorage());
      n.loadDish(healthyDish());
      final h = Harness(dish: n);
      await tester.pumpWidget(h.wrap(const BlankPreviewScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'DEFECT: blank shows a visible text but layout of the banner FAILS '
        '(unbounded width inside InteractiveViewer)', (tester) async {
      phoneSize(tester);
      final n = DishNotifier(storage: RecordingStorage());
      n.loadDish(BadDish.subGramYield());
      final h = Harness(dish: n);
      await tester.pumpWidget(h.wrap(const BlankPreviewScreen()));
      await tester.pump();
      expect(find.text('Проверьте выход и параметры блюда'), findsOneWidget,
          reason: 'the text exists in the tree');
      final errors = <Object>[];
      for (var i = 0; i < 12; i++) {
        final e = tester.takeException();
        if (e != null) errors.add(e);
      }
      expect(errors, isNotEmpty,
          reason: 'BoxConstraints(w=Infinity, 0<=h<=Infinity) handed to the '
              'CalcErrorBanner Container — the banner is never painted');
    });

    testWidgets('export/print are still enabled on an uncalculable dish',
        (tester) async {
      phoneSize(tester);
      final n = DishNotifier(storage: RecordingStorage());
      n.loadDish(BadDish.subGramYield());
      final h = Harness(dish: n);
      await tester.pumpWidget(h.wrap(const BlankPreviewScreen()));
      await tester.pump();
      while (tester.takeException() != null) {}
      final printBtn = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.print_rounded));
      expect(printBtn.onPressed, isNotNull);
      final shareBtn = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.ios_share_rounded));
      expect(shareBtn.onPressed, isNotNull);
    });
  });

  group('control: an empty dish is NOT an error', () {
    testWidgets('empty new dish → no banner, empty-state card', (tester) async {
      phoneSize(tester);
      final n = DishNotifier(storage: RecordingStorage());
      n.createNewDish();
      final h = Harness(dish: n);
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      expect(find.byType(CalcErrorBanner), findsNothing);
      expect(find.text('Рецепт пока пуст'), findsOneWidget);
    });
  });

  group('provider contract', () {
    test('calculationErrorProvider exposes ArgumentError.message verbatim', () {
      final c = ProviderContainer(overrides: [
        dishStorageRepositoryProvider.overrideWithValue(RecordingStorage()),
      ]);
      addTearDown(c.dispose);
      c.read(dishProvider.notifier).loadDish(BadDish.subGramYield());
      expect(c.read(calculationResultProvider), isNull);
      expect(c.read(calculationErrorProvider),
          'Expected finite 1.0..9999999.0');
    });
  });
}
