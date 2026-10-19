import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'culinary_logic_test.dart' show beet, fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('MEGA legacy JSON migrates without library loss', () async {
    final dir = await Directory.systemTemp.createTemp('mega_legacy_');
    try {
      final file = File('${dir.path}/povarspravka_user_dishes.json');
      final dish = fixture(100);
      await file.writeAsString(jsonEncode({
        'activeDraft': dish.toJson(),
        'savedDishes': [dish.toJson()]
      }));
      final s = DishStorageRepository(storageDirectory: dir);
      final legacy = await s.loadAll();
      expect(legacy.savedDishes.single.toJson(), dish.toJson());
      await s.saveAll(
          activeDraft: legacy.activeDraft, savedDishes: legacy.savedDishes);
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(raw['storageVersion'], 1);
      expect(raw['crc32'], isA<int>());
      final reopened =
          await DishStorageRepository(storageDirectory: dir).loadAll();
      expect(reopened.savedDishes.single.toJson(), dish.toJson());
    } finally {
      await dir.delete(recursive: true);
    }
  });
  testWidgets('MEGA five UI swipes leave an empty zero-yield recipe',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final n = DishNotifier();
    for (var i = 0; i < 5; i++) {
      n.addIngredient(beet, 100);
    }
    await tester.pumpWidget(ProviderScope(
        overrides: [dishProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: RecipeEditorScreen())));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      final card = find.byType(Dismissible).first;
      await tester.ensureVisible(card);
      await tester.dragFrom(tester.getTopLeft(card) + const Offset(20, 10),
          const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(n.state.ingredients, isEmpty);
    expect(n.state.effectiveYieldGrams, 0);
    expect(find.text('Выход готового блюда: 0 г'), findsOneWidget);
    await n.flushPendingSaves();
  });
}
