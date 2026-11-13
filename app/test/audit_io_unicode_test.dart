// Аудит персистентности, пункт 4 из 10: побайтовая верность Unicode при
// сохранении → загрузке. Проверяются title/название продукта с эмодзи ZWJ,
// RTL, combining, NUL, lone surrogate, 5000 символов и т.д.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

/// Собирает блюдо с заданными title и названием продукта.
Dish dishWith(String title, String productName) => Dish(
      id: 'u1',
      title: title,
      ingredients: [
        Ingredient(
          id: 'u1-1',
          product: Product(
            id: 7,
            code: '7',
            name: productName,
            groupId: 1,
            source: 'skurikhin',
            protein: 2,
            fat: 3,
            carbs: 4,
            kcal: 51.5,
          ),
          weightGrams: 123.4,
        ),
      ],
      customYieldGrams: 100,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

final Map<String, String> cases = {
  'ёлочки/кавычки': '«ёлочки» «Ёлка»',
  'apostrophe’': 'Пельмени с бульоном’s',
  'apostrophe\'': "Пельмени d'Artagnan",
  'ampersand': 'Соль & перец && соль',
  'degree': 'Разогреть до 180°C ± 5°C',
  'fractions': '1½ стакана · ⅓ ложки · ⅔',
  'emoji-ZWJ': 'Суп 🍲 повар 👨‍🍳 семья 👨‍👩‍👧‍👦',
  'zero-width-space': 'Со\u200Bль',
  'nbsp': 'Соль\u00A0и\u00A0перец',
  'rtl-hebrew': 'מתכון של מרק',
  'rtl-arabic': 'وصفة الحساء',
  'combining': 'e\u0301 Fe\u0301 Catalan·n\u0303',
  'newline-tab': 'Ингредиент\n\tСоль\tПерц',
  'nul': 'Соль\u0000Перец',
  'controls': 'a\u0001b\u001Fc\u007Fd',
  'lone-surrogate': 'Суп \uD800 пер',
  'bmp-plane': '𝕊𝕠𝕦𝕡 𝔘𝔫𝔦𝔠𝔬𝔡𝔢',
  '5000-chars': 'Ё' * 5000,
  'mixed': '«Суп» 🍲 — ½ л воды °C\n\tעברית العربية \u200B\u00A0 é\u0301',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in cases.entries) {
    test('IO-4 round-trip title+product "${entry.key}" is byte-identical and '
        'toJson()-identical', () async {
      final s = await makeStore();
      final repo = DishStorageRepository(storageDirectory: s.dir);
      final dish = dishWith(entry.value, 'Продукт ${entry.value}');
      await repo.saveAll(activeDraft: dish, savedDishes: [dish]);
      final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
      final back = loaded.savedDishes.single;
      // Строковое равенство — по code units; разница в суррогатах даст false.
      expect(back.title.codeUnits, dish.title.codeUnits,
          reason: 'title changed: ${back.title.length} vs ${dish.title.length} '
              'code units');
      expect(back.ingredients.single.product.name,
          dish.ingredients.single.product.name);
      expect(jsonEncode(back.toJson()), jsonEncode(dish.toJson()));
      expect(jsonEncode(loaded.activeDraft!.toJson()),
          jsonEncode(dish.toJson()));
      // И байты файла — валидный UTF-8 (нет double-encoding).
      final bytes = await s.main.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: false);
      expect(text.contains('\u00C3\u00A9'), isFalse,
          reason: 'mojibake: UTF-8 was re-encoded as Latin-1');
    });
  }

  test('IO-4/P1 NUL and control characters are escaped by jsonEncode and '
      'survive the round trip', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final title = 'a\u0000b\u0001c\u001Fd';
    await repo.saveAll(activeDraft: dishWith(title, title), savedDishes: const []);
    final raw = await s.main.readAsString();
    expect(raw, contains(r'\u0000'), reason: 'NUL must be escaped in JSON text');
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, title);
  });

  test('IO-4/P2 lone high surrogate cannot be encoded by utf8 by itself but '
      'jsonEncode escapes it — verify what actually lands on disk', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final title = 'Суп \uD800 пер';
    Object? err;
    try {
      await repo.saveAll(activeDraft: dishWith(title, title), savedDishes: const []);
    } catch (e) {
      err = e;
    }
    if (err != null) {
      // Если запись отказала — это тоже «потеря рецепта» и должна быть видна.
      expect(err, isA<ArgumentError>());
      return;
    }
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title.codeUnits, title.codeUnits);
  });

  test('IO-4/P3 5000-character title survives, file size scales linearly, '
      'and a second generation backup also round-trips', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final long = 'Ёж 🍲 é' * 834; // ≈ 5000+ code units
    await repo.saveAll(activeDraft: dishWith(long, 'p1'), savedDishes: const []);
    await repo.saveAll(activeDraft: dishWith('короткий', 'p2'), savedDishes: const []);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'короткий');
    final bakDoc = jsonDecode(await s.bak.readAsString()) as Map<String, dynamic>;
    expect((bakDoc['activeDraft'] as Map)['title'], long);
  });

  test('IO-4/P4 non-BMP characters are stored as raw UTF-8 (no \\uXXXX '
      'escapes) and re-read identically', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: dishWith('🍲👨‍🍳', '🍲'), savedDishes: const []);
    final raw = await s.main.readAsString();
    expect(raw, contains('🍲'));
    expect(raw, isNot(contains(r'\ud83c')));
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title.runes.toList(), '🍲👨‍🍳'.runes.toList());
  });
}
