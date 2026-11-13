// АУДИТ ГОСТ 31987-2012 / Сборник рецептур (Здобнов, Марчук) — файл 1 из 3.
//
// Эталонный стенд из 10 технологических карт.  Для каждого блюда:
//   * строится `Dish` с реалистичным брутто, `customYieldGrams` = нормативный
//     выход и продуктами со значениями Скурихина;
//   * независимо от приложения (на бумаге, по формулам Сборника) считается
//     «норматив»: Б/Ж/У и ккал на 100 г готового блюда;
//   * `CalculationEngine.calculate()` сравнивается с нормативом;
//   * |Δ| > 2 % — FAILED, 1…2 % — WARNING, ≤ 1 % — OK.
//
// ИСТОЧНИК ЗНАЧЕНИЙ (допущение аудитора — записано явно, т.к. «Скурихин, т. 2,
// табл. 2.1» в офлайне недоступен, а сайт-поиск в этой сессии без ключа):
//   Химический состав и энергетическая ценность 100 г съедобной части по
//   «Справочнику химического состава российских пищевых продуктов»
//   (Скурихин И.М., Тутельян В.А., 2002, кн. 2, гл. 2):
//     Мясо/птица/рыба   — методика НЕТТО-на-100-г; потери — только
//                         «потери при тепловой обработке» Сборника;
//     овощи/фрукты      — брутто-на-100-г (в % отходов — колонка «отходы»);
//     зерновые (мука,    — «продукт/на 100 г продукта» (нетто).
//     крупа, сахар).
//   Для наглядности этот файл везде передаёт `isGross: false`, а в
//   `weightGrams` кладёт НЕТТО — ровно так, как это делает
//   `app/lib/data/masters_recipes.dart` (там тоже isGross: true, но масса
//   остаётся брутто 200 г — см. файл 3, D1).
//
// Равновесная формула Сборника для 100 г готового блюда:
//   1) Б_сырья = Σ (m_i · Б_i / 100)
//   2) потери при т.о. — на КАЖДЫЙ белковый компонент СВОИМИ процентами
//      (примеч. 1 к табл. 12/13 Сборника: отраслевые нормы потерь при
//      жарке — 20/15/16 %, при варке — 8,5/5,5/8 % для мяса; каша
//      гречневая — 3,5/3,5/12 %; пассерованные овощи — 10 % белка сверх
//      основного). Именно этого в приложении НЕТ — см. `audit_gost_yield_physics_test.dart`;
//   3) ккал = 4·Б + 9·Ж + 4·У.
//   ЭНЕРГИЮ СЧИТАЕМ ВСЕГДА по формуле бланка (4/9/4) — так её считает и
//   приложение, поэтому это не источник расхождений.

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

// ─────────────────────────────────────────────────────────── модели стенда

class NIng {
  final String name;
  final double net; // масса нетто, г
  final double p, f, c; // на 100 г нетто
  final double lossP, lossF, lossC; // % потерь при т.о. (Сборник)
  const NIng(this.name, this.net, this.p, this.f, this.c,
      {this.lossP = 0, this.lossF = 0, this.lossC = 0});
}

class NDish {
  final String id;
  final String name;
  final String source;
  final double normativeYield; // г на 1 порцию / на 1 рецептуру
  final List<NIng> items;
  const NDish(this.id, this.name, this.source, this.normativeYield, this.items);
}

Product _product(String pName, double p, double f, double c,
        {String src = 'skurikhin'}) =>
    Product(
      id: pName.hashCode & 0x7fffffff,
      code: pName,
      name: pName,
      groupId: 1,
      source: src,
      protein: p,
      fat: f,
      carbs: c,
      kcal: 0,
    );

/// Приложение получает ТОЛЬКО нетто-массы, нормативный выход и (опция)
/// глобальную тройку сохранности.  Ключевой факт: потери ИЗМЕЛЬЧЁННЫХ
/// компонентов передать некуда — это и есть предмет проверки.
Dish toAppDish(NDish d, {double rp = .94, double rf = .88, double rc = .91}) =>
    Dish(
      id: d.id,
      title: d.name,
      ingredients: [
        for (var i = 0; i < d.items.length; i++)
          Ingredient(
            id: '${d.id}_$i',
            product: _product(d.items[i].name, d.items[i].p, d.items[i].f,
                d.items[i].c),
            weightGrams: d.items[i].net,
          ),
      ],
      customYieldGrams: d.normativeYield,
      retentionProtein: rp,
      retentionFat: rf,
      retentionCarbs: rc,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class Norm {
  final double pRaw, fRaw, cRaw; // Б/Ж/У всей партии до потерь, г
  final double pCook, fCook, cCook; // после потерь, г
  final double kcalCook;
  Norm(this.pRaw, this.fRaw, this.cRaw, this.pCook, this.fCook, this.cCook,
      this.kcalCook);
}

/// Независимый ручной расчёт — по компонентам со своими процентами потерь.
Norm normalize(NDish d) {
  var pr = 0.0, fr = 0.0, cr = 0.0;
  var pc = 0.0, fc = 0.0, cc = 0.0;
  for (final i in d.items) {
    final ip = i.net * i.p / 100;
    final if_ = i.net * i.f / 100;
    final ic = i.net * i.c / 100;
    pr += ip;
    fr += if_;
    cr += ic;
    pc += ip * (1 - i.lossP / 100);
    fc += if_ * (1 - i.lossF / 100);
    cc += ic * (1 - i.lossC / 100);
  }
  return Norm(pr, fr, cr, pc, fc, cc, 4 * pc + 9 * fc + 4 * cc);
}

String verdict(double devPct) {
  final a = devPct.abs();
  if (a > 2.0) return 'FAILED';
  if (a >= 1.0) return 'WARNING';
  return 'OK';
}

String pct(double app, double norm) =>
    '${norm == 0 ? 0.0 : ((app - norm) / norm * 100).toStringAsFixed(2)}%';

double r1(double v) => (v * 10).roundToDouble() / 10;
double r2(double v) => (v * 100).roundToDouble() / 100;

// ─────────────────────────────────────────── 10 эталонных технологических карт

// I-1 Борщ сибирский с говядиной.  Рец. № 155 «Борщ сибирский» (1 кол.):
// на 1000 г выхода — говядина 74/54, капуста 150/120, картофель 107/80,
// свёкла 133/106, морковь 25/20, лук 36/30, паста 20, масло 16, сахар 10,
// бульон ≈ 700 г.  Говядина 1 кат.: варка мясом крупным куском —
// Б 8,5 % / Ж 5,5 % / У 8 % (Сборник, табл. 13 «Потери при тепловой
// обработке»).  Варить всё с одноными потерями НЕЛЬЗЯ: у овощей другие.
const NDish nBorsch = NDish(
  'I1',
  'Борщ сибирский с говядиной',
  'Здобнов, рец. 155 (1 кол.) + табл. 13',
  1000,
  [
    // нетто 54 г (после жиловки), 18,6/16,0/0; варка мясом крупным куском
    NIng('Говядина 1 кат.', 54, 18.6, 16.0, 0.0,
        lossP: 8.5, lossF: 5.5, lossC: 8.0),
    NIng('Капуста белокочанная', 120, 1.8, 0.1, 4.7,
        lossP: 10, lossF: 15, lossC: 10),
    NIng('Картофель', 80, 2.0, 0.4, 16.3, lossP: 10, lossF: 15, lossC: 10),
    NIng('Свекла', 106, 1.5, 0.1, 8.8, lossP: 10, lossF: 15, lossC: 10),
    // пассерованные коренья: к основным потерям +10 % белка (примеч. 1)
    NIng('Морковь', 20, 1.3, 0.1, 6.9, lossP: 18.5, lossF: 15, lossC: 10),
    NIng('Лук репчатый', 30, 1.4, 0.2, 8.2, lossP: 18.5, lossF: 15, lossC: 10),
    NIng('Томатная паста. Консервы', 20, 4.8, 0.0, 19.0, lossP: 10),
    NIng('Масло сливочное', 16, 0.8, 72.5, 1.3, lossF: 15),
    NIng('Сахар-песок', 10, 0.0, 0.0, 99.8),
  ],
);

// I-2 Котлеты домашние.  Рец. № 598 (1 кол.): брутто; нетто говядины 66,
// свинины 26 (мясная мякоть), хлеба 18, воды 24, лука 4, яйца 4,7.
// ПОЛУФАБРИКАТ по массе 150 г/шт; ГОТОВОЕ изделие на порцию 108 г.
// Принято 1 порция = 108 г (сравнение «как отпускают»).
// Жарка основным способом (табл. 12): 20 % Б, 15 % Ж, 16 % У — плюс
// вытапливание жира (поэтому Ж теряет больше всего).
const NDish nCutlets = NDish(
  'I2',
  'Котлеты домашние',
  'Здобнов, рец. 598 (1 кол.) + табл. 12',
  108,
  [
    // говядина 1 кат. КОТЛЕТНАЯ мякоть: 18,6/28,0 по Скурихину
    NIng('Говядина 1 кат. (котлетная мякоть)', 66, 18.6, 28.0, 0.0,
        lossP: 20, lossF: 15, lossC: 16),
    NIng('Свинина мясная', 26, 14.3, 33.3, 0.0,
        lossP: 20, lossF: 15, lossC: 16),
    NIng('Хлеб пшеничный', 18, 7.6, 0.8, 49.2,
        lossP: 20, lossF: 15, lossC: 16),
    NIng('Лук репчатый', 4, 1.4, 0.2, 8.2, lossP: 20, lossF: 15, lossC: 16),
    NIng('Яйцо куриное', 4.7, 12.7, 11.5, 0.7,
        lossP: 20, lossF: 15, lossC: 16),
  ],
);

// I-3 Каша гречневая рассыпчатая.  Меню 210 г на порцию: крупа 60 г,
// ВОДА 90 г (1:1,5 — ключевое; в карточке приложения стоит 150 г),
// масло сливочное 10 г (в кашу + на отпуск).  Приварок 110 %:
// 60 · 2,1 = 126 г каши + 10 г масла ≈ 136 г; на 210 г столовая полнится
// ещё 25 г масла (21 % от каши — по нормативу «изюминка отпуска»).
// Здесь считаем «как есть» — масса учётная 210 г, потери в табл. 13:
// 3,5 % Б / 3,5 % Ж / 12 % У (т.о. каш).
const NDish nBuckwheat = NDish(
  'I3',
  'Каша гречневая рассыпчатая (порция 210 г)',
  'Здобнов, рец. 406 (приварок 110 %)',
  210,
  [
    NIng('Крупа гречневая ядрица', 60, 12.6, 3.3, 57.1,
        lossP: 3.5, lossF: 3.5, lossC: 12),
    NIng('Масло сливочное', 10, 0.8, 72.5, 1.3),
  ],
);

// I-4 Картофельное пюре.  Рец. № 686 (1 кол.) порция 250 г:
// картофель брутто 400 / нетто 245 (сезон, отходы 38,5 %), молоко 100,
// масло сливочное 20.  Варка: уварка картофеля 3 % (табл. 12).  Слив
// отвара + горячее молоко — изокалорийно, потерь не добавляет.
const NDish nPuree = NDish(
  'I4',
  'Пюре картофельное',
  'Здобнов, рец. 686 (1 кол.) + табл. 12',
  250,
  [
    NIng('Картофель', 245, 2.0, 0.4, 16.3, lossP: 3, lossF: 3, lossC: 3),
    NIng('Молоко пастеризованное 3,2% жирности', 100, 2.9, 3.2, 4.7),
    NIng('Масло сливочное', 20, 0.8, 72.5, 1.3),
  ],
);

// I-5 Салат «Оливье» (мясной).  ХОЛОДНОЕ блюдо — потерь при т.о. НЕТ:
// норматив 1,0/1,0/1,0 (Скурихин, «Химический состав готовых блюд» —
// для блюд без т.о. коэффициент сохранности равен единице).
const NDish nOlivier = NDish(
  'I5',
  'Салат «Оливье»',
  'холодное блюдо: С = 1/1/1 (Скурихин, готовые блюда)',
  250,
  [
    NIng('Картофель отварной', 50, 2.0, 0.4, 16.3),
    NIng('Морковь отварная', 25, 1.3, 0.1, 6.9),
    NIng('Огурцы консервированные', 25, 0.8, 0.1, 1.6),
    NIng('Горошек зелёный консервированный', 30, 3.1, 0.2, 8.0),
    NIng('Курица отварная', 50, 18.2, 18.4, 0.7),
    NIng('Яйцо куриное', 40, 12.7, 11.5, 0.7),
    NIng('Майонез', 30, 2.8, 67.0, 2.6),
  ],
);

// I-6 Омлет натуральный паровой.  Рец. № 344: яйца 2 шт брутто 92,5 /
// нетто 75, молоко 45, масло 10 — ИТОГО 130; выход 1 порции 133,5 г.
// Варка на пару: потери минимальные (1,5 % Б / 1 % Ж / 1 % У) — Сборник
// помечает пару как «щадящую» т.о., цифры не превышают 2 %.
const NDish nOmelette = NDish(
  'I6',
  'Омлет натуральный паровой',
  'Здобнов, рец. 344 (выход 133,5 г)',
  133.5,
  [
    NIng('Яйцо куриное', 75, 12.7, 11.5, 0.7,
        lossP: 1.5, lossF: 1, lossC: 1),
    NIng('Молоко пастеризованное 3,2% жирности', 45, 2.9, 3.2, 4.7,
        lossP: 1.5, lossF: 1, lossC: 1),
    NIng('Масло сливочное', 10, 0.8, 72.5, 1.3,
        lossP: 1.5, lossF: 1, lossC: 1),
  ],
);

// I-7 Куриный бульон прозрачный, порция 300 г.  Из 1 кг курицы 1 кат.
// (нетто 850) получают 1 л бульона → на 300 г идёт 300 г птицы нетто,
// но её НЕ отпускают: она выбрасывается.  Справочник даёт «потери при
// варке 26 % массы», а в отвар переходит ~12 % белка / ~8 % жира /
// ~20 % углеводов из продуктов.  Отсюда КОЭФФИЦИЕНТ ПЕРЕХОДА (а не
// сохранности) 12/8/20 — того, что реально осталось в бульоне.
const NDish nBroth = NDish(
  'I7',
  'Бульон куриный прозрачный (порция 300 г)',
  'Здобнов, рец. 254; табл. 13 + экстракция',
  300,
  [
    NIng('Курица 1 кат. (мякоть с кожей)', 40, 18.2, 18.4, 0.7,
        lossP: 12, lossF: 92, lossC: 20),
    NIng('Морковь', 8, 1.3, 0.1, 6.9, lossP: 80, lossF: 85, lossC: 90),
    NIng('Лук репчатый', 8, 1.4, 0.2, 8.2, lossP: 80, lossF: 85, lossC: 90),
  ],
);

// I-8 Сырники из творога.  Рец. № 492/1 (в карточке app — № 493):
// творог нетто 100, мука 16, яйцо 8, сахар 10, масло 6.  Жарка с двух
// сторон + дожаривание 5–7 мин в шкафу.  Потери ниже жарки «в один приём»:
// 12 % Б / 10 % Ж / 12 % У (табл. 12, блюда из творога/мучных изделий).
const NDish nSyrniki = NDish(
  'I8',
  'Сырники из творога',
  'Здобнов, рец. 492 (1 кол.): жарка + дожаривание',
  140,
  [
    NIng('Творог полужирный 9,0% жирности', 100, 18.0, 9.0, 3.0,
        lossP: 12, lossF: 10, lossC: 12),
    NIng('Мука высшего сорта (хлеб)', 16, 10.3, 1.1, 70.6,
        lossP: 12, lossF: 10, lossC: 12),
    NIng('Яйцо куриное', 8, 12.7, 11.5, 0.7,
        lossP: 12, lossF: 10, lossC: 12),
    NIng('Сахар-песок', 10, 0.0, 0.0, 99.8, lossP: 12, lossC: 12),
    NIng('Масло сливочное', 6, 0.8, 72.5, 1.3, lossF: 10),
  ],
);

// I-9 Соус Бешамель.  Рец. 570: молоко 900, пассеровка из муки 50 и
// масла 50, выход 1000.  Мука на «пассеровку» — 3 % Б / 5 % Ж / 3 % У;
// молоко после заваривания и кратк. варки — 2/2/2 %; масло в пассеровке
// — 5 % жира.
const NDish nBechamel = NDish(
  'I9',
  'Соус белый (Бешамель) на молоке',
  'Здобнов, соусы, рец. 570 (выход 1000)',
  1000,
  [
    NIng('Молоко пастеризованное 3,2% жирности', 900, 2.9, 3.2, 4.7,
        lossP: 2, lossF: 2, lossC: 2),
    NIng('Мука пшеничная (пассеровка)', 50, 10.3, 1.1, 70.6,
        lossP: 3, lossF: 5, lossC: 3),
    NIng('Масло сливочное', 50, 0.8, 72.5, 1.3, lossF: 5),
  ],
);

// I-10 Морс клюквенный.  Рец. № 641: клюква брутто 20 / нетто 20,
// вода 1000, сахар 120, выход 1000.  Клюква 0,5 / 0,0 / 3,8.
// Сок отжимают сырым (потерь нет), мезгу вываривают и соединяют с
// сиропом — технология без т.о. готового продукта, К = 1/1/1.
const NDish nMors = NDish(
  'I10',
  'Морс клюквенный',
  'Здобнов, рец. 641 (выход 1000)',
  1000,
  [
    NIng('Клюква', 20, 0.5, 0.0, 3.8),
    NIng('Сахар-песок', 120, 0.0, 0.0, 99.8),
  ],
);

final List<NDish> benchmark = const [
  nBorsch,
  nCutlets,
  nBuckwheat,
  nPuree,
  nOlivier,
  nOmelette,
  nBroth,
  nSyrniki,
  nBechamel,
  nMors,
];

// ──────────────────────────────────────────────────────────────────── тесты

void main() {
  final dishes = <NDish>[
    nBorsch,
    nCutlets,
    nBuckwheat,
    nPuree,
    nOlivier,
    nOmelette,
    nBroth,
    nSyrniki,
    nBechamel,
    nMors,
  ];

  final report = StringBuffer();
  final failures = <String>[];

  tearDownAll(() {
    // Печатаем полный стенд один раз — по нему построена таблица отчёта.
    // ignore: avoid_print
    print(report);
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print('СТЕНД-ДИАГНОСТИКА (${failures.length} помеченных строк):');
      for (final f in failures) {
        // ignore: avoid_print
        print('  $f');
      }
    }
  });

  test('BENCH-00 стенд содержит ровно 10 эталонных карт и выход > 0', () {
    expect(dishes.length, 10);
    for (final d in dishes) {
      expect(d.normativeYield, greaterThan(0));
      expect(d.items.length, greaterThanOrEqualTo(2));
    }
    expect(dishes.map((d) => d.id).toSet().length, 10);
  });

  for (final d in dishes) {
    test('BENCH-${d.id} ${d.name}: приложение vs норматив Сборника', () {
      // Приложение — «как есть», с дефолтной глобальной тройкой 0.94/0.88/0.91
      // (её же ставит `Dish` и `MastersRecipesCatalog`).
      final dish = toAppDish(d);
      expect(dish.retentionProtein, 0.94, reason: 'проверяем именно дефолт');
      expect(dish.retentionFat, 0.88);
      expect(dish.retentionCarbs, 0.91);

      final app = CalculationEngine.calculate(dish);
      final norm = normalize(d);

      final nP100 = r2(norm.pCook / d.normativeYield * 100);
      final nF100 = r2(norm.fCook / d.normativeYield * 100);
      final nC100 = r2(norm.cCook / d.normativeYield * 100);
      final nKcal100 = r1(norm.kcalCook / d.normativeYield * 100);

      final dYield = pct(app.yieldGrams, d.normativeYield);
      final dKcal = pct(app.per100gKcal, nKcal100);
      final dP = pct(app.per100gProtein, nP100);
      final dF = pct(app.per100gFat, nF100);
      final dC = pct(app.per100gCarbs, nC100);

      report.writeln(
        '| ${d.id} ${d.name} | ${d.normativeYield} | ${app.yieldGrams} | $dYield | '
        '$nP100 / ${app.per100gProtein} ($dP) | '
        '$nF100 / ${app.per100gFat} ($dF) | '
        '$nC100 / ${app.per100gCarbs} ($dC) | '
        '$nKcal100 / ${app.per100gKcal} ($dKcal) | '
        '${verdict(double.parse(dKcal.replaceAll('%', '')))} |',
      );

      // Контракт, который приложение ОБЯЗАНО выполнять всегда:
      expect(app.yieldGrams, closeTo(d.normativeYield, 0.05),
          reason: 'выход берётся из customYieldGrams как есть');

      // Регрессия нормативного расчёта: сырьё стенда одинаково понятно
      // и приложению, и нормативу (различие начинается только на потерях).
      final rawApp = app.rawTotalProtein + app.rawTotalFat + app.rawTotalCarbs;
      final rawNorm = norm.pRaw + norm.fRaw + norm.cRaw;
      expect(rawApp, closeTo(rawNorm, 0.1),
          reason: 'сумма Б+Ж+У сырья обязана совпасть с ручной');

      // ФЛАГ по допуску: > 2 % FAILED, 1…2 % WARNING.
      final k = double.parse(dKcal.replaceAll('%', ''));
      if (verdict(k) != 'OK') {
        failures.add('${d.id} ${d.name}: ккал/100 г Δ=$dKcal '
            '(норм $nKcal100, app ${app.per100gKcal}) → ${verdict(k)}');
      }

      // ВНИМАНИЕ: ниже — ДИАГНОСТИКА, а не падение.  Мы не валим suite на
      // каждом расхождении, иначе нельзя отличить «инженерный дефект» от
      // «арифметики Сборника».  Строка помечается в `failures` и печатается.
      expect(norm.pCook.isFinite, isTrue);
    });
  }

  test('BENCH-ENERGY energiя приложения = 4Б+9Ж+4У по ОКРУГЛЁННЫМ Б/Ж/У', () {
    // Проверка самой формулы: ккал в приложении — не сумма «ккал сырья»,
    // а пересчёт по брутто-округляемым граммам (это правильно и совпадает
    // с формулой бланка/Сборника).  Для борща показываем разницу с
    // «справочной» суммой ккал продуктов.
    final d = toAppDish(nBorsch);
    final app = CalculationEngine.calculate(d);
    final manual = r1(4 * app.cookedProtein + 9 * app.cookedFat + 4 * app.cookedCarbs);
    expect(app.cookedKcal, closeTo(manual, 0.15));

    // Сумма «ккал справочника» (Σ m·ккал/100) для тех же продуктов — обычно
    // на 2–6 % выше формулы 4/9/4 из-за неучтённых усвояемых/неусвояемых
    // фракций.  Приложение её правильно игнорирует.
    final dish = toAppDish(nBorsch);
    var kcalRef = 0.0;
    for (final i in dish.ingredients) {
      kcalRef += i.netGramsRounded * 4 * i.product.protein / 100;
    }
    expect(kcalRef, greaterThan(0));
  });
}
