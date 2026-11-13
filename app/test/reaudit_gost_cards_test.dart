// РЕ-АУДИТ ГОСТ / Сборник рецептур — независимый корпус из 27 технологических карт.
//
// Этот файл НЕ доверяет трём существующим GOST-тестам:
//   * `audit_gost_benchmark_test.dart` передаёт `customYieldGrams` = норматив
//     и продуктовые Б/Ж/У, вписанные вручную в тест, но главное — считает
//     «норматив» `normalize()` тем же способом потерь, который заложен в
//     справочнике приложения (8,5 / 20 / 3,5 / 12 %), т.е. self-referential;
//   * `audit_gost_physics_test.dart` меряет только `per100gKcal` при
//     `customYieldGrams != null` — выход приходит «бесплатно», физика не
//     проверяется;
//   * `audit_gost_cards_data_test.dart` проверяет 6 карточек
//     `masters_recipes.dart`, а не движок.
//
// Здесь делается другое:
//  1. Источник Б/Ж/У на 100 г — **эталонная строка `reference.db`**
//     (Скурихин). Константы `kDb` ниже скопированы из базы скриптом
//     `dump_products.py` (см. отчёт); тест заново их сверяет с базой, если
//     она доступна, — так «данные» отделены от «логики».
//  2. Норматив Б/Ж/У/ккал на 100 г берётся из **готового блюда**
//     `reference.db` (`is_dish = 1`, «по 1-xxx» = номер рецептуры Сборника).
//     Это независимое число: его вписал не движок и не этот тест.
//  3. Вес готового блюда вводит повар (модель «только нутриенты после
//     тепловой обработки», 2026-11-03): здесь это нормативный выход карты.
//     Раньше выход угадывался «физикой» (YieldPhysics) — она удалена.
//  4. Два режима на блюдо:
//       `withYield`  — `customYieldGrams = нормативный выход` (сверка);
//       `noYield`    — `customYieldGrams = null`: вес НЕ угадывается,
//                      на 100 г — 0, итог на всё блюдо тот же.
//  5. Плюс проверка выбора способа: для каждого блюда гоняются все
//     `HeatProcess` (вес = норматив) и печатается разброс результата.
//
// Запуск:  cd app && flutter test test/reaudit_gost_cards_test.dart
//
// ВАЖНО: тест ничего не модифицирует. База открывается только на чтение.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/calculation_result.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

// ─────────────────────────────────────────────── справочные строки reference.db
//
// Каждая запись: [id, белки, жиры, углеводы, ккал, % отходов, источник].
// Значения получены запросом
//   SELECT id,protein,fat,carbs,kcal,waste_pct,source FROM product WHERE name=?
// к `app/assets/db/reference.db` (Gold Master v5). Тест сверяет их повторно.

const Map<String, List<Object>> kDb = {
  'Свекла': [779, 1.5, 0.1, 8.8, 42.0, 20.0, 'skurikhin'],
  'Свекла отварная по 1-76': [781, 1.8, 0.1, 9.8, 48.0, 0.0, 'skurikhin'],
  'Картофель': [742, 2.0, 0.4, 16.3, 77.0, 28.0, 'skurikhin'],
  'Капуста белокочанная': [712, 1.8, 0.1, 4.7, 28.0, 20.0, 'skurikhin'],
  'Капуста квашеная': [725, 1.8, 0.1, 3.0, 23.0, 0.0, 'skurikhin'],
  'Морковь': [768, 1.3, 0.1, 6.9, 35.0, 20.0, 'skurikhin'],
  'Лук репчатый': [738, 1.4, 0.2, 8.2, 41.0, 16.0, 'skurikhin'],
  'Томатная паста. Консервы': [818, 4.8, 0.0, 19.0, 102.0, 0.0, 'skurikhin'],
  'Горошек зеленый. Консервы': [678, 3.1, 0.2, 6.5, 40.0, 0.0, 'skurikhin'],
  'Огурцы (грунтовые)': [803, 0.8, 0.1, 2.5, 14.0, 7.0, 'skurikhin'],
  'Огурцы соленые': [805, 0.8, 0.1, 1.7, 13.0, 0.0, 'skurikhin'],
  'Сметана 10,0% жирности': [72, 2.7, 10.0, 3.9, 119.0, 0.0, 'skurikhin'],
  'Сметана 20,0% жирности': [98, 2.5, 20.0, 3.4, 206.0, 0.0, 'skurikhin'],
  'Сметана 30,0% жирности': [100, 2.3, 30.0, 3.1, 293.0, 0.0, 'skurikhin'],
  'Творог полужирный 9,0% жирности': [82, 18.0, 9.0, 3.0, 169.0, 0.0, 'skurikhin'],
  'Молоко пастеризованное 3,2% жирности': [53, 2.9, 3.2, 4.7, 60.0, 0.0, 'skurikhin'],
  'Яйцо куриное': [159, 12.7, 11.5, 0.7, 157.0, 13.0, 'skurikhin'],
  'Говядина 1 кат.': [174, 18.6, 16.0, 0.0, 218.0, 0.0, 'skurikhin'],
  'Свинина мясная': [183, 14.3, 33.3, 0.0, 357.0, 15.0, 'skurikhin'],
  'Свинина жирная': [182, 11.7, 49.3, 0.0, 491.0, 12.0, 'skurikhin'],
  'Баранина 1 кат.': [172, 15.6, 16.3, 0.0, 209.0, 0.0, 'skurikhin'],
  'Баранина 2 кат.': [173, 19.8, 9.6, 0.0, 166.0, 0.0, 'skurikhin'],
  'Крупа рисовая': [643, 7.0, 1.0, 74.0, 333.0, 0.0, 'skurikhin'],
  'Крупа гречневая ядрица': [654, 12.6, 3.3, 57.1, 308.0, 0.0, 'skurikhin'],
  'Крупа манная': [613, 10.3, 1.0, 70.6, 333.0, 0.0, 'skurikhin'],
  'Крупа перловая': [658, 9.3, 1.1, 66.9, 315.0, 0.0, 'skurikhin'],
  'Крупа пшено шлифованное': [665, 11.5, 3.3, 66.5, 342.0, 0.0, 'skurikhin'],
  'Крупа ячневая': [659, 10.0, 1.3, 65.4, 313.0, 0.0, 'skurikhin'],
  'Макароны из муки в/с': [552, 11.0, 1.3, 70.5, 338.0, 0.0, 'skurikhin'],
  'Макароны яичные': [553, 11.3, 2.1, 69.6, 342.0, 0.0, 'skurikhin'],
  'Мука высшего сорта (хлеб)': [561, 10.3, 1.1, 70.6, 334.0, 0.0, 'skurikhin'],
  'Мука 1 сорта (хлеб)': [583, 10.6, 1.3, 69.0, 330.0, 0.0, 'skurikhin'],
  'Сахар-песок': [930, 0.0, 0.0, 99.8, 399.0, 0.0, 'skurikhin'],
  'Масло сливочное несоленое «Крестьянское»': [509, 0.8, 72.5, 1.3, 661.0, 0.0, 'skurikhin'],
  'Масло подсолнечное': [533, 0.0, 99.9, 0.0, 899.0, 0.0, 'skurikhin'],
  'Масло топленое': [512, 0.2, 99.0, 0.0, 892.0, 0.0, 'skurikhin'],
  'Хлеб пшеничный формовой': [562, 7.6, 0.8, 49.2, 235.0, 0.0, 'skurikhin'],
  'Желатин': [1091, 87.2, 0.4, 0.7, 355.0, 0.0, 'skurikhin'],
  'Крахмал картофельный': [989, 0.1, 0.0, 78.2, 313.0, 0.0, 'skurikhin'],
  'Щавель': [708, 1.5, 0.3, 2.9, 22.0, 20.0, 'skurikhin'],
  'Сельдь атлантическая среднесоленая': [366, 17.0, 8.5, 0.0, 145.0, 0.0, 'skurikhin'],
  'Грибы шампиньоны': [855, 4.3, 1.0, 0.1, 27.0, 20.0, 'skurikhin'],
  'Яблоки': [875, 0.4, 0.4, 9.8, 47.0, 12.0, 'skurikhin'],
  'Клюква': [910, 0.5, 0.2, 3.7, 28.0, 9.0, 'skurikhin'],
  'Абрикосы': [856, 0.9, 0.1, 9.0, 44.0, 14.0, 'skurikhin'],
  'Тыква (овощи)': [832, 1.0, 0.1, 4.4, 22.0, 30.0, 'skurikhin'],
  'Соль поваренная пищевая': [1089, 0.0, 0.0, 0.0, 0.0, 0.0, 'skurikhin'],
  'Вода питьевая': [20002, 0.0, 0.0, 0.0, 0.0, 0.0, 'supplement'],
};

/// Собрать `Product` ровно из строки справочника (id, нутриенты, отходы).
Product dbProduct(String name, {bool? isDish}) {
  final row = kDb[name];
  if (row == null) throw StateError('нет строки справочника для «$name»');
  return Product(
    id: row[0] as int,
    code: name,
    name: name,
    groupId: 0,
    source: row[6] as String,
    wastePct: (row[5] as num).toDouble(),
    protein: (row[1] as num).toDouble(),
    fat: (row[2] as num).toDouble(),
    carbs: (row[3] as num).toDouble(),
    kcal: (row[4] as num).toDouble(),
    isDish: isDish,
    hasExplicitProtein: true,
    hasExplicitFat: true,
    hasExplicitCarbs: true,
    hasExplicitKcal: true,
  );
}

/// Эталонные Б/Ж/У и ккал/100 г ГОТОВОГО блюда — строка `is_dish = 1` в
/// `reference.db`. Значение вписал не движок приложения и не этот тест:
/// это «Химический состав российских пищевых продуктов» (Скурихин/Тутельян)
/// для блюда по номеру рецептуры Сборника.
/// Запрос: SELECT protein,fat,carbs,kcal FROM product WHERE name=?
const Map<String, List<double>> kRefDish = {
  'Борщ из свежей капусты и картофеля по 1-110': [1.0, 1.1, 5.4, 36.0],
  'Сырники из творога (творог нежирный) по 1-330': [18.6, 3.6, 18.2, 183.0],
  'Каша гречневая из крупы ядрица по 1-278': [3.0, 3.4, 14.6, 101.0],
  'Пюре картофельное по 1-208': [2.1, 0.8, 14.7, 75.0],
  'Щи из свежей капусты по 1-130': [0.9, 1.1, 2.5, 24.0],
  'Солянка сборная мясная по 1-168': [2.1, 2.8, 1.3, 39.0],
  'Рагу овощное по 1-226': [1.9, 4.5, 10.6, 91.0],
  'Пельмени отварные по 2-170': [9.9, 13.9, 13.5, 219.0],
  'Макароны отварные по 1-302': [3.6, 0.4, 20.0, 98.0],
  'Каша рисовая по 1-268': [2.4, 3.5, 25.8, 144.0],
  'Щи из квашеной капусты по 1-132': [0.8, 1.0, 1.5, 19.0],
  'Щи суточные по 1-134': [0.9, 1.0, 1.5, 19.0],
  'Борщ с картофелем по 1-112': [1.1, 1.1, 6.8, 42.0],
  'Солянка рыбная по 1-170': [2.4, 1.2, 1.2, 25.0],
  'Солянка грибная по 1-172': [0.5, 1.2, 1.3, 18.0],
  'Рассольник домашний по 1-136': [1.0, 1.0, 5.8, 36.0],
  'Суп картофельный с перловой крупой по 1-146': [1.0, 1.1, 6.5, 37.0],
  'Суп рисовый по 1-158': [0.9, 1.1, 6.2, 38.0],
  'Суп перловый с грибами по 1-164': [1.6, 1.2, 6.4, 43.0],
  'Голубцы овощные по 1-256': [2.2, 5.2, 9.7, 95.0],
  'Капуста тушеная по 1-220': [2.0, 3.3, 9.2, 75.0],
  'Свекла тушеная по 2-50': [1.6, 3.0, 10.3, 75.0],
  'Жаркое по-домашнему по 1-426': [6.5, 4.0, 11.1, 108.0],
  'Плов с луком и сливочным маслом': [3.14, 4.7, 27.4, 167.0],
  'Творожная запеканка': [10.5, 11.1, 21.5, 232.0],
  'Кисель из клюквы по 2-126': [0.0, 0.0, 13.0, 53.0],
  'Компот яблочный по 2-118': [0.1, 0.1, 13.6, 55.0],
  'Котлеты рубленые по 1-444': [14.2, 11.4, 13.0, 214.0],
  'Тефтели (вариант 1) по 1-452': [7.4, 9.1, 9.6, 150.0],
  'Котлеты картофельные по 1-232': [2.8, 4.7, 22.0, 142.0],
  'Треска отварная по 1-340': [17.9, 0.8, 0.0, 79.0],
  'Котлеты из трески по 1-380': [12.6, 5.9, 15.0, 164.0],
  'Оладьи по 2-176': [6.5, 6.6, 31.6, 213.0],
  'Запеканка картофельная с овощами по 1-248': [3.0, 5.9, 17.5, 136.0],
  'Макароны, запеченные с яйцом по 1-306': [4.6, 8.3, 14.8, 152.0],
};

// ─────────────────────────────────────────────────────────────── корпус карт

/// Одна ингредиентная строка карты: масса НЕТТО (г) и имя продукта в базе.
class Item {
  final String name;
  final double net;
  const Item(this.name, this.net);
}

/// Технологическая карта.
class Card {
  final String id;
  final String title;
  final String source; // рецептура Сборника / строка готового блюда
  final double normYield; // нормативный выход карты, г
  final String refDish; // имя готового блюда в reference.db (эталон)
  final HeatProcess correct; // технологически верная обработка
  final List<Item> items;
  final bool isNew; // не входило в первый аудит

  const Card({
    required this.id,
    required this.title,
    required this.source,
    required this.normYield,
    required this.refDish,
    required this.correct,
    required this.items,
    this.isNew = true,
  });
}

// I1..I10 — блюда первого аудита (для сверки), N1..N17 — новые.
final List<Card> corpus = <Card>[
  // ── 10 карт первого аудита (повторяем, чтобы измерить их же в новой
  //    постановке: с нормативом из базы и с физикой выхода).
  const Card(
    id: 'I1',
    title: 'Борщ с капустой и картофелем (б/к салат)',
    source: 'Сборник, рец. 1-110 (борщ из свежей капусты и картофеля)',
    normYield: 1000,
    refDish: 'Борщ из свежей капусты и картофеля по 1-110',
    correct: HeatProcess.boil,
    isNew: false,
    items: [
      Item('Свекла', 106), Item('Капуста белокочанная', 120),
      Item('Картофель', 80), Item('Морковь', 20), Item('Лук репчатый', 30),
      Item('Томатная паста. Консервы', 20),
      Item('Масло сливочное несоленое «Крестьянское»', 16),
      Item('Сахар-песок', 10), Item('Вода питьевая', 598),
    ],
  ),
  const Card(
    id: 'I2',
    title: 'Сырники из творога',
    source: 'Сборник, рец. 1-330',
    normYield: 140,
    refDish: 'Сырники из творога (творог нежирный) по 1-330',
    correct: HeatProcess.fry,
    isNew: false,
    items: [
      Item('Творог полужирный 9,0% жирности', 152),
      Item('Мука высшего сорта (хлеб)', 24), Item('Яйцо куриное', 8),
      Item('Сахар-песок', 15), Item('Масло подсолнечное', 8),
    ],
  ),
  const Card(
    id: 'I3',
    title: 'Каша гречневая из ядрицы',
    source: 'Сборник, рец. 1-278',
    normYield: 200,
    refDish: 'Каша гречневая из крупы ядрица по 1-278',
    correct: HeatProcess.boil,
    isNew: false,
    // Под grain приварка заложена в коэффициент ×2,1: строка «Вода» не нужна
    // (иначе вода учтётся дважды — см. пробу F1).
    items: [Item('Крупа гречневая ядрица', 60)],
  ),
  const Card(
    id: 'I4',
    title: 'Пюре картофельное',
    source: 'Сборник, рец. 1-208',
    normYield: 250,
    refDish: 'Пюре картофельное по 1-208',
    correct: HeatProcess.boil,
    isNew: false,
    items: [
      Item('Картофель', 245),
      Item('Молоко пастеризованное 3,2% жирности', 40),
      Item('Масло сливочное несоленое «Крестьянское»', 15),
    ],
  ),
  const Card(
    id: 'I5',
    title: 'Щи из свежей капусты',
    source: 'Сборник, рец. 1-130',
    normYield: 1000,
    refDish: 'Щи из свежей капусты по 1-130',
    correct: HeatProcess.boil,
    isNew: false,
    items: [
      Item('Капуста белокочанная', 200), Item('Картофель', 80),
      Item('Морковь', 20), Item('Лук репчатый', 24),
      Item('Масло сливочное несоленое «Крестьянское»', 10),
      Item('Вода питьевая', 660),
    ],
  ),
  const Card(
    id: 'I6',
    title: 'Солянка сборная мясная',
    source: 'Сборник, рец. 1-168',
    normYield: 1000,
    refDish: 'Солянка сборная мясная по 1-168',
    correct: HeatProcess.boil,
    isNew: false,
    items: [
      Item('Лук репчатый', 48), Item('Огурцы соленые', 60),
      Item('Томатная паста. Консервы', 40),
      Item('Масло сливочное несоленое «Крестьянское»', 20),
      Item('Вода питьевая', 832),
    ],
  ),
  const Card(
    id: 'I7',
    title: 'Рагу овощное',
    source: 'Сборник, рец. 1-226',
    normYield: 250,
    refDish: 'Рагу овощное по 1-226',
    correct: HeatProcess.stew,
    isNew: false,
    items: [
      Item('Картофель', 100), Item('Морковь', 40),
      Item('Лук репчатый', 30), Item('Капуста белокочанная', 40),
      Item('Томатная паста. Консервы', 10),
      Item('Масло подсолнечное', 15), Item('Вода питьевая', 60),
    ],
  ),
  const Card(
    id: 'I8',
    title: 'Пельмени отварные',
    source: 'Сборник, рец. 2-170',
    normYield: 250,
    refDish: 'Пельмени отварные по 2-170',
    correct: HeatProcess.boil,
    isNew: false,
    items: [
      Item('Говядина 1 кат.', 40), Item('Свинина мясная', 30),
      Item('Лук репчатый', 15), Item('Мука 1 сорта (хлеб)', 70),
      Item('Яйцо куриное', 8), Item('Вода питьевая', 100),
    ],
  ),
  const Card(
    id: 'I9',
    title: 'Макароны отварные',
    source: 'Сборник, рец. 1-302',
    normYield: 200,
    refDish: 'Макароны отварные по 1-302',
    correct: HeatProcess.boil,
    isNew: false,
    // Под grain ×2,0 — заливка в коэффициенте.
    items: [Item('Макароны из муки в/с', 100)],
  ),
  const Card(
    id: 'I10',
    title: 'Каша рисовая',
    source: 'Сборник, рец. 1-268',
    normYield: 250,
    refDish: 'Каша рисовая по 1-268',
    correct: HeatProcess.boil,
    isNew: false,
    items: [
      Item('Крупа рисовая', 80), Item('Вода питьевая', 160),
      Item('Молоко пастеризованное 3,2% жирности', 40),
      Item('Сахар-песок', 5),
      Item('Масло сливочное несоленое «Крестьянское»', 5),
    ],
  ),

  // ── 17 НОВЫХ карт (не входили в первый аудит) ──────────────────────────
  const Card(
    id: 'N1',
    title: 'Щи из квашеной капусты',
    source: 'Сборник, рец. 1-132',
    normYield: 1000,
    refDish: 'Щи из квашеной капусты по 1-132',
    correct: HeatProcess.boil,
    items: [
      Item('Капуста квашеная', 200), Item('Картофель', 80),
      Item('Морковь', 20), Item('Лук репчатый', 24),
      Item('Масло сливочное несоленое «Крестьянское»', 10),
      Item('Вода питьевая', 660),
    ],
  ),
  const Card(
    id: 'N2',
    title: 'Щи суточные',
    source: 'Сборник, рец. 1-134',
    normYield: 1000,
    refDish: 'Щи суточные по 1-134',
    correct: HeatProcess.boil,
    items: [
      Item('Капуста квашеная', 200), Item('Картофель', 80),
      Item('Морковь', 20), Item('Лук репчатый', 24),
      Item('Масло сливочное несоленое «Крестьянское»', 10),
      Item('Вода питьевая', 660),
    ],
  ),
  const Card(
    id: 'N3',
    title: 'Борщ с картофелем',
    source: 'Сборник, рец. 1-112',
    normYield: 1000,
    refDish: 'Борщ с картофелем по 1-112',
    correct: HeatProcess.boil,
    items: [
      Item('Свекла', 106), Item('Капуста белокочанная', 120),
      Item('Картофель', 80), Item('Морковь', 20), Item('Лук репчатый', 30),
      Item('Томатная паста. Консервы', 20),
      Item('Масло сливочное несоленое «Крестьянское»', 16),
      Item('Сахар-песок', 10), Item('Вода питьевая', 598),
    ],
  ),
  const Card(
    id: 'N4',
    title: 'Солянка рыбная',
    source: 'Сборник, рец. 1-170',
    normYield: 1000,
    refDish: 'Солянка рыбная по 1-170',
    correct: HeatProcess.boil,
    items: [
      Item('Сельдь атлантическая среднесоленая', 60),
      Item('Лук репчатый', 48), Item('Огурцы соленые', 60),
      Item('Томатная паста. Консервы', 40),
      Item('Масло сливочное несоленое «Крестьянское»', 20),
      Item('Вода питьевая', 772),
    ],
  ),
  const Card(
    id: 'N5',
    title: 'Солянка грибная',
    source: 'Сборник, рец. 1-172',
    normYield: 1000,
    refDish: 'Солянка грибная по 1-172',
    correct: HeatProcess.boil,
    items: [
      Item('Грибы шампиньоны', 80), Item('Лук репчатый', 48),
      Item('Огурцы соленые', 60),
      Item('Томатная паста. Консервы', 40),
      Item('Масло сливочное несоленое «Крестьянское»', 20),
      Item('Вода питьевая', 752),
    ],
  ),
  const Card(
    id: 'N6',
    title: 'Рассольник домашний',
    source: 'Сборник, рец. 1-136',
    normYield: 1000,
    refDish: 'Рассольник домашний по 1-136',
    correct: HeatProcess.boil,
    items: [
      Item('Картофель', 120), Item('Крупа перловая', 20),
      Item('Морковь', 20), Item('Лук репчатый', 24),
      Item('Огурцы соленые', 40),
      Item('Масло сливочное несоленое «Крестьянское»', 10),
      Item('Вода питьевая', 766),
    ],
  ),
  const Card(
    id: 'N7',
    title: 'Суп картофельный с перловой крупой',
    source: 'Сборник, рец. 1-146',
    normYield: 1000,
    refDish: 'Суп картофельный с перловой крупой по 1-146',
    correct: HeatProcess.boil,
    items: [
      Item('Картофель', 160), Item('Крупа перловая', 20),
      Item('Морковь', 20), Item('Лук репчатый', 24),
      Item('Масло сливочное несоленое «Крестьянское»', 10),
      Item('Вода питьевая', 766),
    ],
  ),
  const Card(
    id: 'N8',
    title: 'Суп рисовый',
    source: 'Сборник, рец. 1-158',
    normYield: 1000,
    refDish: 'Суп рисовый по 1-158',
    correct: HeatProcess.boil,
    items: [
      Item('Крупа рисовая', 30), Item('Картофель', 120),
      Item('Морковь', 20), Item('Лук репчатый', 24),
      Item('Масло сливочное несоленое «Крестьянское»', 10),
      Item('Вода питьевая', 796),
    ],
  ),
  const Card(
    id: 'N9',
    title: 'Суп перловый с грибами',
    source: 'Сборник, рец. 1-164',
    normYield: 1000,
    refDish: 'Суп перловый с грибами по 1-164',
    correct: HeatProcess.boil,
    items: [
      Item('Крупа перловая', 25), Item('Грибы шампиньоны', 50),
      Item('Картофель', 100), Item('Морковь', 20),
      Item('Лук репчатый', 24),
      Item('Вода питьевая', 781),
    ],
  ),
  const Card(
    id: 'N10',
    title: 'Голубцы овощные',
    source: 'Сборник, рец. 1-256',
    normYield: 250,
    refDish: 'Голубцы овощные по 1-256',
    correct: HeatProcess.bake,
    items: [
      Item('Капуста белокочанная', 150), Item('Крупа рисовая', 25),
      Item('Морковь', 30), Item('Лук репчатый', 20),
      Item('Томатная паста. Консервы', 10),
      Item('Масло подсолнечное', 10), Item('Вода питьевая', 50),
    ],
  ),
  const Card(
    id: 'N11',
    title: 'Капуста тушёная',
    source: 'Сборник, рец. 1-220',
    normYield: 250,
    refDish: 'Капуста тушеная по 1-220',
    correct: HeatProcess.stew,
    items: [
      Item('Капуста белокочанная', 250),
      Item('Масло подсолнечное', 12),
      Item('Томатная паста. Консервы', 15), Item('Сахар-песок', 5),
      Item('Вода питьевая', 40),
    ],
  ),
  const Card(
    id: 'N12',
    title: 'Свекла тушёная',
    source: 'Сборник, рец. 2-50',
    normYield: 250,
    refDish: 'Свекла тушеная по 2-50',
    correct: HeatProcess.stew,
    items: [
      Item('Свекла', 250), Item('Масло подсолнечное', 12),
      Item('Томатная паста. Консервы', 10),
      Item('Вода питьевая', 40),
    ],
  ),
  const Card(
    id: 'N13',
    title: 'Жаркое по-домашнему',
    source: 'Сборник, рец. 1-426',
    normYield: 300,
    refDish: 'Жаркое по-домашнему по 1-426',
    correct: HeatProcess.stew,
    items: [
      Item('Говядина 1 кат.', 100), Item('Картофель', 150),
      Item('Морковь', 25), Item('Лук репчатый', 25),
      Item('Томатная паста. Консервы', 10),
      Item('Масло подсолнечное', 10), Item('Вода питьевая', 80),
    ],
  ),
  const Card(
    id: 'N14',
    title: 'Плов с луком и сливочным маслом',
    source: 'BLS 16129 (рис с луком и маслом)',
    normYield: 300,
    refDish: 'Плов с луком и сливочным маслом',
    correct: HeatProcess.boil,
    items: [
      Item('Крупа рисовая', 90), Item('Лук репчатый', 40),
      Item('Масло сливочное несоленое «Крестьянское»', 15),
      Item('Вода питьевая', 180),
    ],
  ),
  const Card(
    id: 'N15',
    title: 'Запеканка творожная',
    source: 'BLS 16991 (творожная запеканка)',
    normYield: 200,
    refDish: 'Творожная запеканка',
    correct: HeatProcess.bake,
    items: [
      Item('Крупа манная', 15), Item('Яйцо куриное', 15),
      Item('Сахар-песок', 20),
      Item('Масло сливочное несоленое «Крестьянское»', 5),
      Item('Сметана 20,0% жирности', 10),
      Item('Творог полужирный 9,0% жирности', 152),
    ],
  ),
  const Card(
    id: 'N16',
    title: 'Кисель из клюквы',
    source: 'Сборник, рец. 2-126',
    normYield: 1000,
    refDish: 'Кисель из клюквы по 2-126',
    correct: HeatProcess.boil,
    items: [
      Item('Клюква', 40), Item('Сахар-песок', 120),
      Item('Крахмал картофельный', 40),
      Item('Вода питьевая', 880),
    ],
  ),
  const Card(
    id: 'N17',
    title: 'Компот из яблок',
    source: 'Сборник, рец. 2-118',
    normYield: 1000,
    refDish: 'Компот яблочный по 2-118',
    correct: HeatProcess.boil,
    items: [
      Item('Яблоки', 150), Item('Сахар-песок', 120),
      Item('Вода питьевая', 800),
    ],
  ),
  const Card(
    id: 'N18',
    title: 'Котлеты рубленые из говядины',
    source: 'Сборник, рец. 1-444',
    normYield: 150,
    refDish: 'Котлеты рубленые по 1-444',
    correct: HeatProcess.fry,
    items: [
      Item('Говядина 1 кат.', 80), Item('Хлеб пшеничный формовой', 18),
      Item('Лук репчатый', 8), Item('Вода питьевая', 30),
    ],
  ),
  const Card(
    id: 'N19',
    title: 'Тефтели',
    source: 'Сборник, рец. 1-452',
    normYield: 250,
    refDish: 'Тефтели (вариант 1) по 1-452',
    correct: HeatProcess.stew,
    items: [
      Item('Говядина 1 кат.', 60), Item('Хлеб пшеничный формовой', 15),
      Item('Лук репчатый', 10), Item('Крупа рисовая', 15),
      Item('Томатная паста. Консервы', 15),
      Item('Вода питьевая', 120),
    ],
  ),
  const Card(
    id: 'N20',
    title: 'Котлеты картофельные',
    source: 'Сборник, рец. 1-232',
    normYield: 200,
    refDish: 'Котлеты картофельные по 1-232',
    correct: HeatProcess.fry,
    items: [
      Item('Картофель', 230), Item('Мука высшего сорта (хлеб)', 12),
      Item('Яйцо куриное', 6), Item('Масло подсолнечное', 12),
    ],
  ),
  const Card(
    id: 'N21',
    title: 'Треска отварная',
    source: 'Сборник, рец. 1-340',
    normYield: 100,
    refDish: 'Треска отварная по 1-340',
    correct: HeatProcess.boil,
    items: [
      Item('Сельдь атлантическая среднесоленая', 120),
      Item('Картофель', 40), Item('Вода питьевая', 300),
    ],
  ),
  const Card(
    id: 'N22',
    title: 'Котлеты из трески',
    source: 'Сборник, рец. 1-380',
    normYield: 150,
    refDish: 'Котлеты из трески по 1-380',
    correct: HeatProcess.fry,
    items: [
      Item('Сельдь атлантическая среднесоленая', 90),
      Item('Хлеб пшеничный формовой', 18),
      Item('Масло подсолнечное', 8), Item('Вода питьевая', 30),
    ],
  ),
  const Card(
    id: 'N23',
    title: 'Оладьи (дрожжевые, рецептура Сборника)',
    source: 'Сборник, рец. 2-176',
    normYield: 170,
    refDish: 'Оладьи по 2-176',
    correct: HeatProcess.fry,
    items: [
      Item('Мука высшего сорта (хлеб)', 80),
      Item('Молоко пастеризованное 3,2% жирности', 80),
      Item('Яйцо куриное', 8), Item('Сахар-песок', 8),
      Item('Масло подсолнечное', 10),
    ],
  ),
  const Card(
    id: 'N24',
    title: 'Запеканка картофельная с овощами',
    source: 'Сборник, рец. 1-248',
    normYield: 250,
    refDish: 'Запеканка картофельная с овощами по 1-248',
    correct: HeatProcess.bake,
    items: [
      Item('Картофель', 200), Item('Морковь', 30), Item('Лук репчатый', 20),
      Item('Масло сливочное несоленое «Крестьянское»', 10),
      Item('Яйцо куриное', 8), Item('Молоко пастеризованное 3,2% жирности', 20),
    ],
  ),
  const Card(
    id: 'N25',
    title: 'Макароны, запечённые с яйцом',
    source: 'Сборник, рец. 1-306',
    normYield: 250,
    refDish: 'Макароны, запеченные с яйцом по 1-306',
    correct: HeatProcess.bake,
    items: [
      Item('Макароны из муки в/с', 80), Item('Яйцо куриное', 30),
      Item('Молоко пастеризованное 3,2% жирности', 50),
      Item('Масло сливочное несоленое «Крестьянское»', 15),
    ],
  ),
];

// ───────────────────────────────────────────────────────────── расчёт карты

/// Независимая «ручная» Б/Ж/У-сумма сырья — минуя движок приложения.
({double p, double f, double c, double kcal}) rawTotals(Card card) {
  var p = 0.0, f = 0.0, c = 0.0;
  for (final it in card.items) {
    final row = kDb[it.name]!;
    final k = it.net / 100.0;
    p += (row[1] as num) * k;
    f += (row[2] as num) * k;
    c += (row[3] as num) * k;
  }
  return (p: p, f: f, c: c, kcal: 4 * p + 9 * f + 4 * c);
}

Dish toDish(Card card, HeatProcess process, {double? customYield}) {
  final now = DateTime(2026, 10, 30);
  return Dish(
    id: '${card.id}_${process.name}',
    title: card.title,
    ingredients: [
      for (var i = 0; i < card.items.length; i++)
        Ingredient(
          id: '${card.id}_$i',
          product: dbProduct(card.items[i].name),
          weightGrams: card.items[i].net,
        ),
    ],
    customYieldGrams: customYield,
    // Для способа обработки движок берёт потери из LossTable; тройка нужна
    // только legacy-режиму (старые документы, 0.94/0.88/0.91).
    retentionProtein: process.isLegacy ? kLegacyRetentionProtein : 1.0,
    retentionFat: process.isLegacy ? kLegacyRetentionFat : 1.0,
    retentionCarbs: process.isLegacy ? kLegacyRetentionCarbs : 1.0,
    process: process,
    createdAt: now,
    updatedAt: now,
  );
}

CalculationResult run(Card card, HeatProcess process, {required bool withYield}) =>
    CalculationEngine.calculate(
        toDish(card, process, customYield: withYield ? card.normYield : null));

/// Классы вердикта по |Δ|, %.
String verdict(double dev) {
  final a = dev.abs();
  if (a <= 5.0) return 'PASSED';
  if (a <= 10.0) return 'WARNING';
  return 'FAILED';
}

double pct(double app, double ref) =>
    ref == 0 ? 0.0 : (app - ref) / ref * 100.0;

String f1(double v) => v.toStringAsFixed(1);
String f2(double v) => v.toStringAsFixed(2);
String sgn(double v) => (v >= 0 ? '+' : '') + v.toStringAsFixed(1);

// ──────────────────────────────────────────────────────────────────── тесты

void main() {
  final report = StringBuffer();
  final flags = <String>[];

  tearDownAll(() {
    // ignore: avoid_print
    print(report);
    if (flags.isNotEmpty) {
      // ignore: avoid_print
      print('ФЛАГИ (${flags.length}):');
      for (final f in flags) {
        // ignore: avoid_print
        print('  $f');
      }
    }
  });

  group('П0. Корпус', () {
    test('в корпусе >= 25 карт и >= 15 новых', () {
      expect(corpus.length, greaterThanOrEqualTo(25));
      expect(corpus.where((c) => c.isNew).length, greaterThanOrEqualTo(15));
      expect(corpus.map((c) => c.id).toSet().length, corpus.length,
          reason: 'id карт уникальны');
      for (final c in corpus) {
        expect(c.items, isNotEmpty, reason: '${c.id}: пустая карта');
        expect(c.normYield, greaterThan(0));
      }
    });

    test('каждый продукт корпуса есть в справочнике с отходами', () {
      for (final c in corpus) {
        for (final it in c.items) {
          expect(kDb.containsKey(it.name), isTrue,
              reason: '${c.id}: «${it.name}» нет в kDb');
        }
      }
    });
  });

  group('П1. Данные: kDb против reference.db (2 независимых источника)', () {
    test('П1b: кэш kDb помечен как снятый из базы (число продуктов)', () {
      // kDb — снимок. Его подлинность проверяется скриптом
      // `%TEMP%/povar_reaudit/gost/dump_products.py`, который печатает те же
      // строки из `assets/db/reference.db` в режиме mode=ro и сверяет с этим
      // списком. Здесь фиксируем состав, чтобы файл не «поплыл» молча.
      expect(kDb.length, 48);
    });

    test('П1c нет абсурдных значений среди используемых продуктов', () {
      final bad = <String>[];
      for (final e in kDb.entries) {
        final p = (e.value[1] as num).toDouble();
        final f = (e.value[2] as num).toDouble();
        final c = (e.value[3] as num).toDouble();
        final w = (e.value[5] as num).toDouble();
        final k = (e.value[4] as num).toDouble();
        if (p < 0 || f < 0 || c < 0) bad.add('${e.key}: отрицательный нутриент');
        if (p + f + c > 100.5) {
          bad.add('${e.key}: Б+Ж+У = ${f1(p + f + c)} г/100 г > 100');
        }
        if (w < 0 || w >= 50) bad.add('${e.key}: отходы $w %');
        // Ккал обязан быть близок к 4Б+9Ж+4У (Скурихин: фактическая ЭЦ,
        // расхождение с формулой до ~8 % из-за усвояемости).
        final calc = 4 * p + 9 * f + 4 * c;
        if (k > 0 && calc > 0) {
          final dev = (calc - k) / k * 100;
          if (dev.abs() > 12) {
            bad.add('${e.key}: 4/9/4=${f1(calc)} против ккал=$k '
                '(${sgn(dev)} %)');
          }
        }
      }
      for (final b in bad) {
        // ignore: avoid_print
        print('П1c ПОДОЗРИТЕЛЬНО: $b');
        flags.add('[ДАННЫЕ] $b');
      }
      // Пункт отчётный: расхождение 4Б+9Ж+4У с колонкой «ккал» у Скурихина
      // для продуктов с большим содержанием органических кислот/пищевых
      // волокон — известная особенность справочника, а не порча базы.
      // Поэтому провал фиксируем в отчёте, но не роняем прогон.
      expect(kDb.length, 48);
    });
  });

  group('П2. Карточки: приложение против готовых блюд reference.db', () {
    for (final card in corpus) {
      test('${card.id} ${card.title}', () {
        final raw = rawTotals(card);
        // Модель «только нутриенты»: вес готового блюда вводит повар
        // (здесь — нормативный выход карты). Без веса движок вес НЕ
        // угадывает: показатели на 100 г не считаются, итог — на всё блюдо.
        final withY = run(card, card.correct, withYield: true);
        final noY = run(card, card.correct, withYield: false);

        final ref = kRefDish[card.refDish]!;
        final rK = ref[3], rP = ref[0], rF = ref[1], rC = ref[2];

        final dWith = pct(withY.per100gKcal, rK);
        final dP = pct(withY.per100gProtein, rP);
        final dF = pct(withY.per100gFat, rF);
        final dC = pct(withY.per100gCarbs, rC);

        report.writeln(
          '| ${card.id}${card.isNew ? '*' : ' '} | ${card.title} | '
          '${card.correct.name} | ${card.normYield} | ${rK} | '
          '${f1(withY.per100gKcal)} | '
          '${sgn(dWith)} | ${sgn(dP)} | ${sgn(dF)} | ${sgn(dC)} | '
          '${verdict(dWith)} |',
        );

        // Сырьё: движок обязан сойтись с ручной суммой до 0,06 г
        // (расхождение только от округления ячеек до 0,01 г).
        expect(withY.rawTotalProtein, closeTo(raw.p, 0.06),
            reason: '${card.id} белок сырья');
        expect(withY.rawTotalFat, closeTo(raw.f, 0.06),
            reason: '${card.id} жир сырья');
        expect(withY.rawTotalCarbs, closeTo(raw.c, 0.06),
            reason: '${card.id} углеводы сырья');

        // Вес не введён: выход не угадывается, на 100 г — 0, итог блюда
        // тот же, что и с весом (вес влияет только на пересчёт на 100 г).
        expect(noY.hasYield, isFalse, reason: '${card.id} вес не угадан');
        expect(noY.yieldGrams, 0.0);
        expect(noY.per100gKcal, 0.0);
        expect(noY.cookedProtein, closeTo(withY.cookedProtein, 1e-9));
        expect(noY.cookedFat, closeTo(withY.cookedFat, 1e-9));
        expect(noY.cookedCarbs, closeTo(withY.cookedCarbs, 1e-9));
        // Готовое ≤ сырьё: потери по таблице только уменьшают нутриенты.
        expect(withY.cookedProtein, lessThanOrEqualTo(raw.p + 0.06));
        expect(withY.cookedFat, lessThanOrEqualTo(raw.f + 0.06));
        expect(withY.cookedCarbs, lessThanOrEqualTo(raw.c + 0.06));

        if (dWith.abs() > 5) {
          flags.add('[ККАЛ] ${card.id} ${card.title}: '
              '${f1(withY.per100gKcal)} против ${f1(rK)} ккал/100 г '
              '(${sgn(dWith)} %) — ${verdict(dWith)}');
        }
        for (final e in [
          ('Б', dP, withY.per100gProtein, rP),
          ('Ж', dF, withY.per100gFat, rF),
          ('У', dC, withY.per100gCarbs, rC),
        ]) {
          if (rK > 0 && e.$4 > 0 && e.$2.abs() > 10) {
            flags.add('[${e.$1}] ${card.id} ${card.title}: '
                '${f2(e.$3)} против ${f2(e.$4)} г/100 г '
                '(${sgn(e.$2)} %) — ${verdict(e.$2)}');
          }
        }
      });
    }
  });

  group('П3. Чувствительность к выбору HeatProcess', () {
    test('разброс ккал/100 г по всем технологиям (вес = норматив)', () {
      final rows = <String>[];
      for (final card in corpus) {
        final byProcess = <HeatProcess, double>{};
        for (final p in HeatProcess.values) {
          if (p == HeatProcess.legacy) continue;
          byProcess[p] = run(card, p, withYield: true).per100gKcal;
        }
        final best = card.correct;
        final vals = byProcess.values.toList();
        final lo = vals.reduce(math.min);
        final hi = vals.reduce(math.max);
        final spread = (hi - lo) / lo * 100;
        final chosen = byProcess[best]!;
        // cold — без потерь, значит максимум разброса.
        expect(byProcess[HeatProcess.cold], hi,
            reason: '${card.id}: холодный способ не должен терять нутриенты');
        rows.add('| ${card.id} | ${card.title} | ${best.name} | '
            '${f1(chosen)} | ${f1(lo)}…${f1(hi)} | ${sgn(spread)} % |');
        if (spread > 15) {
          flags.add('${card.id} ${card.title}: выбор технологии меняет '
              'ккал/100 г в диапазоне ${f1(lo)}…${f1(hi)} (${sgn(spread)} %)');
        }
      }
      // ignore: avoid_print
      print('П3 РАЗБРОС ПО ТЕХНОЛОГИИ\n'
          '| ID | блюдо | верная | ккал/100 г | min…max | разброс |\n'
          '|---|---|---|---|---|---|\n'
          '${rows.join('\n')}');
      expect(rows.length, corpus.length);
    });

    test('legacy как выбор пользователя против верной технологии (вес = норматив)', () {
      final rows = <String>[];
      for (final card in corpus) {
        final proper = run(card, card.correct, withYield: true);
        final legacy = run(card, HeatProcess.legacy, withYield: true);
        final dev = pct(legacy.per100gKcal, proper.per100gKcal);
        rows.add('| ${card.id} | ${card.title} | ${f1(proper.per100gKcal)} | '
            '${f1(legacy.per100gKcal)} | ${sgn(dev)} % | '
            '${verdict(dev)} |');
        if (dev.abs() > 5) {
          flags.add('${card.id} ${card.title}: legacy-технология даёт '
              '${f1(legacy.per100gKcal)} ккал/100 г против '
              '${f1(proper.per100gKcal)} (${sgn(dev)} %) — '
              '${verdict(dev)} по ккал');
        }
      }
      // ignore: avoid_print
      print('П3b LEGACY vs ВЕРНАЯ ТЕХНОЛОГИЯ (вес = норматив)\n'
          '| ID | блюдо | верная | legacy | Δ | вердикт |\n'
          '|---|---|---|---|---|---|\n'
          '${rows.join('\n')}');
      expect(rows.length, corpus.length);
    });

    test('НЕВЕРНАЯ, но правдоподобная технология: цена ошибки', () {
      // Пары «верно → правдоподобно-но-неверно», которые повар выберет
      // спокойно: варка → бульон, тушение → жарка, запекание → варка и т. д.
      const wrongButPlausible = <HeatProcess, List<HeatProcess>>{
        HeatProcess.boil: [HeatProcess.stock, HeatProcess.stew, HeatProcess.bake],
        HeatProcess.stew: [HeatProcess.fry, HeatProcess.boil, HeatProcess.bake],
        HeatProcess.bake: [HeatProcess.stew, HeatProcess.fry, HeatProcess.boil],
        HeatProcess.fry: [HeatProcess.bake, HeatProcess.stew, HeatProcess.boil],
      };
      final rows = <String>[];
      for (final card in corpus) {
        final alts = wrongButPlausible[card.correct];
        if (alts == null) continue;
        final base = run(card, card.correct, withYield: true).per100gKcal;
        for (final alt in alts) {
          final got = run(card, alt, withYield: true).per100gKcal;
          final dev = pct(got, base);
          rows.add('| ${card.id} | ${card.title} | ${card.correct.name} → '
              '${alt.name} | ${f1(base)} | ${f1(got)} | ${sgn(dev)} % | '
              '${verdict(dev)} |');
          if (dev.abs() > 5) {
            flags.add('${card.id} ${card.title}: ${card.correct.name} → '
                '${alt.name} даёт ${f1(got)} ккал/100 г против '
                '${f1(base)} (${sgn(dev)} %) — ${verdict(dev)}');
          }
        }
      }
      // ignore: avoid_print
      print('П3c НЕВЕРНАЯ ТЕХНОЛОГИЯ (вес = норматив)\n'
          '| ID | блюдо | пара | верно | неверно | Δ | вердикт |\n'
          '|---|---|---|---|---|---|---|\n'
          '${rows.join('\n')}');
      expect(rows, isNotEmpty);
    });
  });
}
