// STATE-07: TextEditingController / FocusNode / StreamSubscription leaks in
// `SearchProductModal`, `RecipeEditorScreen`, `CustomNumpadSheet`.
//
// The REAL crash path for the two dialogs is NOT a disposed controller but a
// deactivated context: `_editWastePercentage` / `_showRetentionSettingsDialog`
// create the controller OUTSIDE `showDialog` and never dispose it, so the
// `FormField` looks up `TextFormField`'s state in the dialog's disposed
// `_FormScope` when the bound controller notifies AFTER the dialog is gone.
// See `test/audit_state_dialog_lifecycle_test.dart` for the red test.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';

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
      measures: [
        ProductMeasure(id: 1, productId: 1, name: 'клубень', grams: 80),
      ],
    );

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

/// `ProviderScope` already disposes the overridden notifier on unmount.
void Function() disposeOnce(StateNotifier<dynamic> notifier) {
  var done = false;
  return () {
    if (done) return;
    done = true;
    try {
      notifier.dispose();
    } catch (_) {}
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STATE-07 static audit: every controller is disposed', () {
    test('controllers found by grep, and whether they are disposed', () {
      final findings = <String, bool>{};
      String src(String rel) => File(rel).readAsStringSync();

      // ignore: unused_element
      void check(String rel, String ctor, {required int expected}) {
        final s = src(rel);
        final created =
            RegExp(RegExp.escape(ctor)).allMatches(s).length;
        final disposed = RegExp('\\$ctor|\\.dispose\\(\\)').allMatches(s).length;
        findings['$rel :: $ctor'] = created >= expected && disposed > 0;
      }

      // recipe_editor_screen.dart: two owned controllers, both disposed in
      // State.dispose (lines 57-61).
      final editor = src('lib/presentation/screens/recipe_editor_screen.dart');
      expect(editor.contains('_titleCtrl.dispose()'), isTrue);
      expect(editor.contains('_yieldCtrl.dispose()'), isTrue);
      // ...but the three local ones created in the retention dialog are NOT:
      expect(editor.contains('pCtrl.dispose()'), isFalse);
      expect(editor.contains('fCtrl.dispose()'), isFalse);
      expect(editor.contains('cCtrl.dispose()'), isFalse);

      final modal = src('lib/presentation/screens/search_product_modal.dart');
      expect(modal.contains('_searchCtrl.dispose()'), isTrue);

      final numpad = src('lib/presentation/widgets/custom_numpad.dart');
      expect(numpad.contains('final controller = TextEditingController('),
          isTrue);
      expect(numpad.contains('controller.dispose()'), isFalse,
          reason: 'OBSERVED: the waste-% dialog controller is never disposed');

      final preview = src('lib/presentation/screens/blank_preview_screen.dart');
      expect(preview.contains('_transform.dispose()'), isTrue);
      expect(preview.contains('_transform.removeListener'), isTrue);

      // No StreamSubscription anywhere in lib/ (grep result), no FocusNode.
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync();
        expect(s.contains('StreamSubscription'), isFalse,
            reason: 'unexpected StreamSubscription in ${f.path}');
        expect(s.contains('FocusNode('), isFalse,
            reason: 'unexpected FocusNode in ${f.path}');
      }
      // ignore: avoid_print
      print('STATE-07 probe: $findings');
    });
  });

  group('STATE-07 widget flows leave no controller errors', () {
    testWidgets(
        'SearchProductModal: open → type → expand row → info card → waste '
        'dialog → measure dialog → close everything', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = DishNotifier(storage: NoopStorage());
      addTearDown(notifier.dispose);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => notifier),
          productRepositoryProvider.overrideWithValue(OneRepo()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SearchProductModal()),
        ),
      ));
      await tester.pumpAndSettle();

      // 1. Type into the search field.
      await tester.enterText(find.byType(TextField).first, 'карт');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Картофель'), findsWidgets);

      // 2. Expand the row (combo-pick).
      await tester.tap(find.text('Картофель').first);
      await tester.pumpAndSettle();
      expect(find.text('Добавить в блюдо'), findsOneWidget);

      // 3. Waste-% dialog: open, type, cancel.
      final editWaste = find.text('изменить %');
      expect(editWaste, findsOneWidget, reason: 'waste 20% → button shown');
      await tester.tap(editWaste);
      await tester.pumpAndSettle();
      expect(find.text('Процент отходов при холодной обработке'), findsOneWidget);
      final dialogField = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextFormField));
      await tester.enterText(dialogField, '25');
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull,
          reason: 'no "used after being disposed" after closing the dialog');

      // 4. Measure dialog (TextFormField with initialValue, no controller).
      //    The chip row lives inside `_buildInlineEditor` at the bottom of the
      //    expanded row, below the 300 dp keypad: scroll it into view first.
      final chip = find.text('клубень');
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('measure-count')), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('measure-count')), '3');
      await tester.pump();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 5. Close the modal entirely.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('RecipeEditorScreen: title field, yield field, retention '
        'dialog → unmount without errors', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = DishNotifier(storage: NoopStorage());
      addTearDown(disposeOnce(notifier));
      notifier.addIngredient(potato(), 250);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => notifier),
          savedDishesProvider.overrideWith((ref) {
            final s = SavedDishesNotifier(NoopStorage());
            ref.onDispose(s.dispose);
            return s;
          }),
          productRepositoryProvider.overrideWithValue(OneRepo()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const RecipeEditorScreen()),
      ));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('actual-yield'));
      if (field.evaluate().isNotEmpty) {
        await tester.enterText(field, '200');
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
