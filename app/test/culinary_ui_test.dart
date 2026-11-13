import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/macro_summary_bar.dart';
import 'culinary_logic_test.dart' show beet;
import 'support/test_artifacts.dart';

/// Одна временная папка снимков на прогон файла: `../audit_artifacts/`
/// рабочего дерева больше не трогаем (аудит D14).
Directory get _shotsDir => _shots ??= artifactDirOnce('culinary_ui');
Directory? _shots;

/// Удаление папки снимков в конце файла (регистрируется в `main`).
void _dropShots() {
  final dir = _shots;
  if (dir != null && dir.existsSync()) dir.deleteSync(recursive: true);
}

final boundary = GlobalKey();
Future<void> prepare(WidgetTester tester,
    {double width = 390,
    double scale = 1,
    bool dark = false,
    bool empty = false,
    // Снимки и числа ниже (94/88/91 %, «Задать фактический выход») — экран
    // старого расчёта (legacy). Новый расчёт — тесты «New dish …» в конце.
    HeatProcess process = HeatProcess.legacy}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final loader = FontLoader('Arial')
    ..addFont(rootBundle.load('assets/fonts/arial.ttf'));
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final notifier = DishNotifier();
  notifier.setHeatProcess(process);
  if (!empty) notifier.addIngredient(beet, 100);
  await tester.pumpWidget(ProviderScope(
      overrides: [dishProvider.overrideWith((ref) => notifier)],
      child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const RecipeEditorScreen()))));
  await tester.pumpAndSettle();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  // Скриншот делается только когда в дереве есть исходный RepaintBoundary
  // (helper prepare); в синтетических деревьях (отдельная проверка полосы
  // итогов) кадра для съёмки нет — это не повод валить тест.
  if (boundary.currentContext == null) return;
  await tester.runAsync(() async {
    final box =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await box.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = _shotsDir;
    await File('${dir.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byType(Scrollable).first);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

void main() {
  tearDownAll(_dropShots);
  testWidgets('Automatic mode, both tabs and inspector use same numbers',
      (tester) async {
    await prepare(tester);
    expect(find.text('Выход готового блюда: 100 г'), findsOneWidget);
    expect(find.byKey(const ValueKey('actual-yield')), findsNothing);
    await screenshot(tester, 'light_auto_top');

    // Редизайн (docs/DESIGN_UX_AUDIT.md P1-6): в нижнем доке — компактная
    // строка «После т.о.», а полные три ступени (Сырьё → После т.о. →
    // Порция) с переключателем «На всё блюдо / На 100 г» открываются
    // кнопкой «Инспектор расчёта». Ниже проверяется ровно тот же контракт
    // чисел, но там, где эти цифры теперь живут.
    await reveal(tester, find.byType(MacroSummaryBar));
    expect(find.text('После т.о. · на всё блюдо'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('macro-Белки'))).data,
        '1,41 г');
    await screenshot(tester, 'light_auto_summary');

    // Полная полоса «Сырьё → После т.о. → Порция» в текущем дереве.
    final r = CalculationEngine.calculate(
        ProviderScope.containerOf(tester.element(find.byType(RecipeEditorScreen)))
            .read(dishProvider));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SingleChildScrollView(child: MacroSummaryBar(result: r)))));
    await tester.pumpAndSettle();
    expect(find.text('На всё блюдо (100 г)'), findsOneWidget);
    expect(find.text('На 100 г готового блюда'), findsOneWidget);
    await tester.tap(find.text('На 100 г готового блюда'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('macro-Белки'))).data,
        '1,41 г');
    expect(find.text('Сырьё'), findsOneWidget);
    expect(find.text('После т.о.'), findsOneWidget);
    expect(find.text('Порция'), findsOneWidget);

    // Инспектор открывается из полной полосы — проверяем по шагам
    // (1,50 × 94% = 1,41 г и энергетическая формула) в этом же дереве.
    await tester.tap(find.text('Инспектор расчёта'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Белки: 1,50 × 94% = 1,41 г'), findsOneWidget);
    expect(find.text('1,41 × 4 + 0,09 × 9 + 8,01 × 4 = 38,5 ккал'),
        findsOneWidget);
    await screenshot(tester, 'inspector');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Explicit yield, invalid entry, dilution, and reset',
      (tester) async {
    await prepare(tester);
    await tester.tap(find.text('Задать фактический выход'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('actual-yield'));
    await reveal(tester, input);
    await tester.enterText(input, '200');
    await tester.pumpAndSettle();
    expect(find.textContaining('+100 г жидкости'), findsOneWidget);
    await screenshot(tester, 'light_dilution');
    await tester.enterText(input, '0');
    await tester.pumpAndSettle();
    expect(find.textContaining('Сохранён прежний выход.'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)));
    expect(container.read(dishProvider).effectiveYieldGrams, 200);
    await tester.enterText(input, 'NaN');
    await tester.pumpAndSettle();
    expect(container.read(dishProvider).effectiveYieldGrams, 200);
    await reveal(tester, find.text('Задать фактический выход'));
    await tester.tap(find.text('Задать фактический выход'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('actual-yield')), findsNothing);
    expect(container.read(dishProvider).effectiveYieldGrams, 100);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Swipe removal supports undo and automatic mass', (tester) async {
    await prepare(tester);
    final card = find.byType(Dismissible);
    await reveal(tester, card);
    await tester.drag(card, const Offset(-500, 0));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)));
    expect(container.read(dishProvider).ingredients, isEmpty);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(container.read(dishProvider).ingredients.length, 1);
    expect(container.read(dishProvider).effectiveYieldGrams, 100);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 800.0]) {
      testWidgets('Layout ${dark ? 'dark' : 'light'} $width', (tester) async {
        await prepare(tester, width: width, dark: dark);
        await screenshot(
            tester, '${dark ? 'dark' : 'light'}_${width.toInt()}_top');
        await reveal(tester, find.byType(MacroSummaryBar));

        await screenshot(
            tester, '${dark ? 'dark' : 'light'}_${width.toInt()}_summary');
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Large text remains scrollable', (tester) async {
    await prepare(tester, width: 320, scale: 1.5);
    await screenshot(tester, 'large_text_top');
    await reveal(tester, find.byType(MacroSummaryBar));

    await screenshot(tester, 'large_text');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Empty recipe has zero yield', (tester) async {
    await prepare(tester, empty: true);
    expect(find.text('Выход готового блюда: 0 г'), findsOneWidget);
    await tester.tap(find.text('Задать фактический выход'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('actual-yield')), findsNothing);
    await screenshot(tester, 'empty');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Saved explicit yield is visible and explained on load',
      (tester) async {
    await prepare(tester);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)));
    final dish = c.read(dishProvider);
    c
        .read(dishProvider.notifier)
        .loadDish(dish.copyWith(id: 'saved', customYieldGrams: 50));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('actual-yield'));
    expect(tester.widget<TextField>(input).controller!.text, '50');
    expect(find.textContaining('50% уварка'), findsOneWidget);
    expect(
        CalculationEngine.calculate(c.read(dishProvider)).per100gProtein, 2.82);
  });
  testWidgets('200 g raw, 100 g yield shows evaporation and 77 kcal',
      (tester) async {
    await prepare(tester);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)));
    final n = c.read(dishProvider.notifier);
    n.updateIngredient(c.read(dishProvider).ingredients.single.id, 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Задать фактический выход'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('actual-yield')), '100');
    await tester.pumpAndSettle();
    expect(find.textContaining('50% уварка'), findsOneWidget);
    await reveal(tester, find.textContaining('50% уварка'));
    await screenshot(tester, 'evaporation');
    // Переключатель «на 100 г» живёт в полной полосе (три ступени),
    // которая открывается «Инспектором расчёта» из нижнего дока.
    final r = CalculationEngine.calculate(c.read(dishProvider));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SingleChildScrollView(child: MacroSummaryBar(result: r)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('На 100 г готового блюда'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('macro-Белки'))).data,
        '2,82 г');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('macro-Энергия'))).data,
        '77,0 ккал');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Pushed route has a back button without clipped title',
      (tester) async {
    await prepare(tester, width: 320);
    final context = tester.element(find.byType(RecipeEditorScreen));
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RecipeEditorScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await screenshot(tester, 'navigation_320');
    expect(tester.takeException(), isNull);
  });

  // Новый расчёт (задача 2026-11-03): потери Б/Ж/У — по таблице для группы
  // каждого продукта, вес готового блюда вводит повар.
  testWidgets('New dish (cold): weight field always shown, nothing guessed',
      (tester) async {
    await prepare(tester, process: HeatProcess.cold);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)));
    expect(c.read(dishProvider).process, HeatProcess.cold);
    expect(find.text('Вес готового блюда не указан'), findsOneWidget);
    expect(find.text('Задать фактический выход'), findsNothing);
    final input = find.byKey(const ValueKey('actual-yield'));
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(find.text('Укажите вес готового блюда'), findsOneWidget);
    final r = CalculationEngine.calculate(c.read(dishProvider));
    expect(r.hasYield, isFalse);
    expect([r.cookedProtein, r.cookedFat, r.cookedCarbs], [1.5, .1, 8.8],
        reason: 'без обработки потерь нет');
    await reveal(tester, find.byType(MacroSummaryBar));
    expect(find.text('После т.о. · на всё блюдо'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('macro-Белки'))).data,
        '1,50 г');
    await screenshot(tester, 'new_cold_no_weight');
    await reveal(tester, input);
    await tester.enterText(input, '80');
    await tester.pumpAndSettle();
    expect(c.read(dishProvider).effectiveYieldGrams, 80);
    expect(find.text('Выход готового блюда: 80 г'), findsOneWidget);
    await tester.enterText(input, '');
    await tester.pumpAndSettle();
    expect(c.read(dishProvider).customYieldGrams, isNull);
    expect(c.read(dishProvider).effectiveYieldGrams, 0,
        reason: 'пустое поле — вес не указан, сумма нетто не подставляется');
    expect(find.text('Вес готового блюда не указан'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('New dish (boil): table losses per group, label and weight',
      (tester) async {
    await prepare(tester, process: HeatProcess.boil);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)));
    final n = c.read(dishProvider.notifier);
    final id = c.read(dishProvider).ingredients.single.id;
    // «Свекла» фикстуры записана с group_id 1 (молочные у Скурихина) —
    // повар переводит её в корнеплоды вручную.
    n.setIngredientGroup(id, LossGroup.rootTuber);
    await tester.pumpAndSettle();
    final label = find.textContaining(
        'корнеплоды и картофель (вручную) · варка — Б 2 %, Ж 2 %, У 5 %');
    await reveal(tester, label);
    expect(label, findsOneWidget);
    // МР 2.3.0419-26, прил. 4: корнеплоды, варка — потери 2 / 2 / 5 %.
    final r = CalculationEngine.calculate(c.read(dishProvider));
    expect([r.cookedProtein, r.cookedFat, r.cookedCarbs], [1.47, .1, 8.36]);
    expect(r.cookedKcal, 40.2);
    expect(r.hasYield, isFalse);
    await reveal(tester, find.byType(MacroSummaryBar));
    expect(tester.widget<Text>(find.byKey(const ValueKey('macro-Белки'))).data,
        '1,47 г');
    final input = find.byKey(const ValueKey('actual-yield'));
    await reveal(tester, input);
    await tester.enterText(input, '90');
    await tester.pumpAndSettle();
    final r2 = CalculationEngine.calculate(c.read(dishProvider));
    expect(r2.yieldGrams, 90);
    expect(r2.cookedProtein, 1.47,
        reason: 'вес готового блюда не меняет БЖУ на всё блюдо');
    expect(r2.per100gProtein, 1.63);
    await screenshot(tester, 'new_boil_weight');
    expect(tester.takeException(), isNull);
  });
}



