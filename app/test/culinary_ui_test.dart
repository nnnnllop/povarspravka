import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/macro_summary_bar.dart';
import 'culinary_logic_test.dart' show beet;

final boundary = GlobalKey();
Future<void> prepare(WidgetTester tester,
    {double width = 390,
    double scale = 1,
    bool dark = false,
    bool empty = false}) async {
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
  await tester.runAsync(() async {
    final box =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await box.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('../audit_artifacts/culinary_ui');
    await dir.create(recursive: true);
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
  testWidgets('Automatic mode, both tabs and inspector use same numbers',
      (tester) async {
    await prepare(tester);
    expect(find.text('Выход готового блюда: 100 г'), findsOneWidget);
    expect(find.byKey(const ValueKey('actual-yield')), findsNothing);
    await screenshot(tester, 'light_auto_top');

    await reveal(tester, find.byType(MacroSummaryBar));

    expect(find.text('На всё блюдо (100 г)'), findsOneWidget);
    expect(find.text('На 100 г готового блюда'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('macro-Белки'))).data,
        '1,41 г');
    await tester.tap(find.text('На 100 г готового блюда'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('macro-Белки'))).data,
        '1,41 г');
    await screenshot(tester, 'light_auto_summary');
    await tester.tap(find.text('Инспектор расчёта'));
    await tester.pumpAndSettle();
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
    await reveal(tester, find.byType(MacroSummaryBar));
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
}
