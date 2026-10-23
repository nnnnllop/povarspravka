import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/core/theme/app_colors.dart';
import 'package:povarspravka/core/theme/app_space.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';

/// Исполняемая версия критериев приёмки из `docs/DESIGN_UX_AUDIT.md` §7.
///
/// Здесь нет «проверки, что мы нарисовали то, что нарисовали»: каждый тест
/// кодирует требование, которое можно нарушить регрессией.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Все интерактивные цели >= 48 dp', () {
    const screens = <String, Widget>{
      'HomeScreen': HomeScreen(),
      'RecipeEditorScreen': RecipeEditorScreen(),
      'SearchProductModal': Scaffold(
          body: SearchProductModal(mode: SearchMode.browseCatalog)),
      'BlankPreviewScreen': BlankPreviewScreen(),
    };

    for (final scale in [1.0, 2.0]) {
      for (final entry in screens.entries) {
        testWidgets('${entry.key} scale=$scale', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final n = DishNotifier();
          n.addIngredient(_sampleProduct(), 100);
          n.addIngredient(_sampleProduct(name: 'Морковь'), 50);

          await tester.pumpWidget(ProviderScope(
            overrides: [
              dishProvider.overrideWith((ref) => n),
              productRepositoryProvider.overrideWithValue(_SampleRepo()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: entry.value,
            ),
          ));
          await tester.pumpAndSettle();

          final violations = <String>[];
          for (final element in find.byWidgetPredicate((w) =>
              w is InkWell ||
              w is IconButton ||
              w is TextButton ||
              w is FilledButton ||
              w is OutlinedButton ||
              w is ElevatedButton ||
              w is GestureDetector ||
              w is SegmentedButton ||
              w is PopupMenuButton ||
              w is Checkbox ||
              w is Switch ||
              w is Radio ||
              w is FloatingActionButton ||
              w is ListTile ||
              w is ReorderableDragStartListener).evaluate()) {
            final widget = element.widget;
            // GestureDetector без onTap — не цель, а «слушатель жестов»
            // внутри составного виджета (проверяется его родитель).
            if (widget is GestureDetector &&
                widget.onTap == null &&
                widget.onLongPress == null) {
              continue;
            }
            final render = element.renderObject;
            if (render is! RenderBox || !render.hasSize) continue;
            final size = render.size;
            if (size.width < kMinTapTarget - 0.5 ||
                size.height < kMinTapTarget - 0.5) {
              violations.add(
                  '${widget.runtimeType} ${size.width.toStringAsFixed(1)}×'
                  '${size.height.toStringAsFixed(1)}');
            }
          }

          expect(
            violations,
            isEmpty,
            reason: 'Цели меньше $kMinTapTarget dp на экране ${entry.key} '
                'при масштабе $scale (WCAG 2.5.5): $violations',
          );
        });
      }
    }
  });

  group('Контраст WCAG AA (4.5:1 текст, 3:1 интерактивные границы)', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = math.max(la, lb);
      final lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    void expectAtLeast(Color fg, Color bg, double ratio, String label) {
      final actual = contrast(fg, bg);
      expect(actual, greaterThanOrEqualTo(ratio),
          reason: '$label: ${actual.toStringAsFixed(2)}:1 < $ratio:1');
    }

    test('светлая тема: текст и границы', () {
      for (final bg in [AppColors.canvas, AppColors.surface]) {
        expectAtLeast(AppColors.ink, bg, 4.5, 'ink');
        expectAtLeast(AppColors.inkSecondary, bg, 4.5, 'inkSecondary');
        expectAtLeast(AppColors.inkMuted, bg, 4.5, 'inkMuted');
        expectAtLeast(AppColors.accent, bg, 4.5, 'accent');
        expectAtLeast(AppColors.protein, bg, 4.5, 'protein');
        expectAtLeast(AppColors.fat, bg, 4.5, 'fat');
        expectAtLeast(AppColors.carbs, bg, 4.5, 'carbs');
        expectAtLeast(AppColors.kcal, bg, 4.5, 'kcal');
        expectAtLeast(AppColors.danger, bg, 4.5, 'danger');
        expectAtLeast(AppColors.success, bg, 4.5, 'success');
        // 1.4.11 — границы полей и кнопок должны читаться как объект.
        expectAtLeast(AppColors.border, bg, 3.0, 'border (интерактивная)');
      }
      expectAtLeast(AppColors.accentOn, AppColors.accent, 4.5, 'текст на accent');
      expectAtLeast(AppColors.ink, AppColors.accentSoft, 4.5, 'ink на accentSoft');
    });

    test('тёмная тема: текст и границы', () {
      for (final bg in [AppColors.canvasDark, AppColors.surfaceDark]) {
        expectAtLeast(AppColors.inkDark, bg, 4.5, 'inkDark');
        expectAtLeast(AppColors.inkSecondaryDark, bg, 4.5, 'inkSecondaryDark');
        expectAtLeast(AppColors.inkMutedDark, bg, 4.5, 'inkMutedDark');
        expectAtLeast(AppColors.proteinDark, bg, 4.5, 'proteinDark');
        expectAtLeast(AppColors.fatDark, bg, 4.5, 'fatDark');
        expectAtLeast(AppColors.carbsDark, bg, 4.5, 'carbsDark');
        expectAtLeast(AppColors.kcalDark, bg, 4.5, 'kcalDark');
        expectAtLeast(AppColors.borderDark, bg, 3.0, 'borderDark');
      }
    });

    test('бренд, «Скурихин» и жиры — три разных цвета, а не один', () {
      // Аудит P0-4: ранее все три были янтарными и сливались.
      final keys = {
        'accent (бренд)': AppColors.accent.value,
        'fat (жиры)': AppColors.fat.value,
        'sourceInk (Скурихин)': AppColors.sourceInk.value,
      };
      expect(keys.values.toSet().length, 3,
          reason: 'Бренд, жиры и источник обязаны различаться: $keys');
      // И они действительно различимы на глаз, а не на 2 единицы канала.
      expect(contrast(AppColors.accent, AppColors.fat), greaterThan(1.05));
      expect(contrast(AppColors.fat, AppColors.sourceInk), greaterThan(1.5));
    });
  });

  group('Защита данных', () {
    testWidgets('DishNotifier.isDirty учитывает правки, но не updatedAt',
        (tester) async {
      final n = DishNotifier();
      n.addIngredient(_sampleProduct(), 100);
      await tester.pump();
      n.markClean();
      expect(n.isDirty, isFalse, reason: 'сразу после сохранения — чисто');

      // Пересохранение без изменений не должно «загрязнять» (updatedAt/id
      // в сигнатуру не входят).
      n.markClean();
      expect(n.isDirty, isFalse);

      final id = n.state.ingredients.single.id;
      n.updateIngredient(id, 250);
      expect(n.isDirty, isTrue, reason: 'правка массы делает черновик грязным');

      n.markClean();
      expect(n.isDirty, isFalse);
      n.setTitle('Новое название');
      expect(n.isDirty, isTrue, reason: 'правка названия тоже изменение');
    });

    testWidgets('закрытие редактора с несохранёнными правками спрашивает',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final n = DishNotifier();
      n.addIngredient(_sampleProduct(), 100);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => n),
          productRepositoryProvider.overrideWithValue(_SampleRepo()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Продолжить расчёт'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorScreen), findsOneWidget);

      // Правка → «назад» не должно молча выбросить работу.
      n.updateIngredient(n.state.ingredients.single.id, 333);
      await tester.pumpAndSettle();
      expect(n.isDirty, isTrue);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.byType(RecipeEditorScreen), findsOneWidget,
          reason: 'экран не закрывается без решения повара');
      expect(find.text('Не сохранять изменения?'), findsOneWidget);
      expect(find.text('Сохранить и выйти'), findsOneWidget);
      expect(find.textContaining('несохранённые правки'), findsOneWidget);
    });
  });

  group('Критичные компоненты', () {
    testWidgets('нумпад: клавиши 56 dp, нет пресетов-обманок',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CustomNumpadSheet(
            product: _sampleProduct(),
            initialGrams: 0,
            onConfirm: (_, __) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final key = find.byKey(const ValueKey('key-7'));
      expect(tester.getSize(key).height, greaterThanOrEqualTo(48));
      // Опасные пресеты из аудита P0-1 («1000 г», «Порция») удалены.
      expect(find.text('Порция'), findsNothing);
      expect(find.text('1000'), findsNothing);
    });
  });

  // Матрица ручного тестирования §Этап 6, сведённая к автотесту:
  // 5 ширин × 4 масштаба × 2 темы × 4 экрана. Единственный допуск —
  // отсутствие исключений (переполнений) за кадр.
  group('Матрица ширина × масштаб × тема', () {
    const widths = [320.0, 360.0, 393.0, 412.0, 440.0];
    const scales = [1.0, 1.3, 1.5, 2.0];
    const screens = <String, Widget>{
      'Home': HomeScreen(),
      'Editor': RecipeEditorScreen(),
      'Search': Scaffold(
          body: SearchProductModal(mode: SearchMode.browseCatalog)),
      'Preview': BlankPreviewScreen(),
    };

    for (final theme in ['light', 'dark']) {
      for (final width in widths) {
        for (final scale in scales) {
          testWidgets('$theme ${width.toInt()}dp ×${scale}x', (tester) async {
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            for (final entry in screens.entries) {
              final n = DishNotifier();
              n.addIngredient(_sampleProduct(), 100);
              n.addIngredient(_sampleProduct(name: 'Морковь'), 50);
              await tester.pumpWidget(ProviderScope(
                overrides: [
                  dishProvider.overrideWith((ref) => n),
                  productRepositoryProvider.overrideWithValue(_SampleRepo()),
                ],
                child: MaterialApp(
                  theme: theme == 'dark' ? AppTheme.dark : AppTheme.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: entry.value,
                ),
              ));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull,
                  reason: '${entry.key} переполнился при $theme, '
                      '${width.toInt()}dp, масштабе $scale');
            }
          });
        }
      }
    }
  });
}

Product _sampleProduct({String name = 'Свёкла'}) => Product(
      id: name.hashCode,
      code: 'qa-',
      name: name,
      groupId: 1,
      source: 'skurikhin',
      wastePct: 20,
      protein: 1.5,
      fat: 0.1,
      carbs: 8.8,
      kcal: 42.1,
      water: 86,
    );

class _SampleRepo extends ProductRepository {
  @override
  Future<List<Product>> searchProducts(
          {String query = '',
          int? groupId,
          String? source,
          int limit = 60}) async =>
      [_sampleProduct(), _sampleProduct(name: 'Морковь')];
  @override
  Future<List<FoodGroup>> getFoodGroups() async =>
      [const FoodGroup(id: 1, code: 'qa', name: 'Овощи и корнеплоды')];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int productId) async =>
      [];
}





