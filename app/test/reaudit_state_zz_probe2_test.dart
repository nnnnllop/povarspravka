// Regression coverage (A3-TEST-02, converted from diagnostic probes) for
// `RecipeEditorScreen` (waste=100) and `BlankPreviewScreen` (healthy dish) at
// standard and compact phone widths without frame exceptions or ErrorWidgets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';

import 'reaudit_state_support.dart';

Dish waste100Dish() => dishWith(
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

void main() {
  for (final size in [const Size(390, 844), const Size(320, 640)]) {
    testWidgets('EDITOR waste=100 renders (no ErrorWidget) at $size',
        (tester) async {
      phoneSize(tester, size: size);
      final n = DishNotifier(storage: RecordingStorage());
      n.loadDish(waste100Dish());
      final h = Harness(dish: n);
      await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
      await tester.pump();
      final errs = <Object>[];
      for (var i = 0; i < 5; i++) {
        final e = tester.takeException();
        if (e != null) errs.add(e);
      }
      expect(errs, isEmpty, reason: 'unexpected frame exception at $size');
      expect(find.byType(ErrorWidget), findsNothing);
      expect(
        find.text('Проверьте выход и параметры блюда'),
        findsOneWidget,
      );
    });

    testWidgets('BLANK renders for a healthy dish at $size', (tester) async {
      phoneSize(tester, size: size);
      final n = DishNotifier(storage: RecordingStorage());
      n.loadDish(healthyDish());
      final h = Harness(dish: n);
      await tester.pumpWidget(h.wrap(const BlankPreviewScreen()));
      await tester.pump();
      final errs = <Object>[];
      for (var i = 0; i < 5; i++) {
        final e = tester.takeException();
        if (e != null) errs.add(e);
      }
      expect(errs, isEmpty, reason: 'unexpected frame exception at $size');
      expect(find.byType(ErrorWidget), findsNothing);
      expect(
        find.text('Проверьте выход и параметры блюда'),
        findsNothing,
      );
    });
  }
}
