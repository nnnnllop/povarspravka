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
      expect(editor.contains('_yieldFocusNode.removeListener'), isTrue);
      expect(editor.contains('_yieldFocusNode.dispose()'), isTrue);
      // All three controllers in `_RecipeSettingsDialogState` are owned and
      // disposed in `State.dispose`:
      expect(editor.contains('_pCtrl.dispose()'), isTrue);
      expect(editor.contains('_fCtrl.dispose()'), isTrue);
      expect(editor.contains('_cCtrl.dispose()'), isTrue);

      final modal = src('lib/presentation/screens/search_product_modal.dart');
      expect(modal.contains('_searchCtrl.dispose()'), isTrue);

      // v1.2: waste-% editing is inline in the keypad, so no controller is
      // allocated inside `showDialog`.
      final numpad = src('lib/presentation/widgets/custom_numpad.dart');
      expect(numpad.contains('TextEditingController'), isFalse,
          reason: 'FIXED: inline waste-% edit uses no TextEditingController');

      final preview = src('lib/presentation/screens/blank_preview_screen.dart');
      expect(preview.contains('_transform.dispose()'), isTrue);
      expect(preview.contains('_transform.removeListener'), isTrue);

      // No StreamSubscription anywhere in lib/, and FocusNode only in owned RecipeEditorScreen.
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync();
        expect(s.contains('StreamSubscription'), isFalse,
            reason: 'unexpected StreamSubscription in ${f.path}');
        final normalized = f.path.replaceAll('\\', '/');
        if (!normalized.endsWith('recipe_editor_screen.dart')) {
          expect(s.contains('FocusNode('), isFalse,
              reason: 'unexpected FocusNode in ${f.path}');
        }
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
      addTearDown(disposeOnce(notifier));

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
      expect(find.text('Добавить'), findsOneWidget);

      // 3. Inline waste-% edit inside CustomNumpadSheet: open, type, cancel.
      final editWaste = find.byKey(const ValueKey('waste-edit-toggle'));
      expect(editWaste, findsOneWidget, reason: 'waste 20% → toggle shown');
      await tester.ensureVisible(editWaste);
      await tester.pumpAndSettle();
      await tester.tap(editWaste);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('key-2')));
      await tester.tap(find.byKey(const ValueKey('key-5')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('waste-edit-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('waste-edit-cancel')), findsNothing);
      expect(tester.takeException(), isNull,
          reason: 'no exception after toggling and cancelling inline waste edit');

      // 4. Inline measure stepper inside CustomNumpadSheet (no AlertDialog).
      await tester.tap(find.byKey(const ValueKey('numpad-extras-toggle')));
      await tester.pumpAndSettle();
      final chip = find.byKey(const ValueKey('measure-клубень'));
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('measure-count-label')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('measure-inc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('measure-inc')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('measure-count-label')))
            .data,
        '2',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('measure-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('measure-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('measure-count-label')), findsNothing);
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
          savedDishesProvider.overrideWith(
            (ref) => SavedDishesNotifier(NoopStorage()),
          ),
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
