import 'models/loss_group.dart';
import 'models/heat_process.dart';

/// Таблица потерь белков, жиров и углеводов при тепловой обработке:
/// `группа × способ → (потери Б %, Ж %, У %)`.
///
/// Формула расчёта (решение владельца продукта; МР 2.3.0419-26, формула 8):
///
///     Б_готов = Σ Б_сырьё_i × (100 − потериБ(группа_i, способ)) / 100
///
/// так же для Ж и У; ккал = 4Б + 9Ж + 4У.
///
/// Правила переноса источника в таблицу (подробно — `docs/COEFFICIENT_SOURCES.md`):
///  * углеводы: для круп, бобовых, корнеплодов и картофеля, муки и хлеба —
///    столбец «крахмал», для овощей, фруктов и сахара — «моно- и дисахариды»;
///  * прочерк «–» в источнике = потерь нет (0 %): в примере расчёта МР
///    для отварной говядины сохранность углеводов принята 100 % ([LossSource.mrFormula]);
///  * варка растительных — строка «без слива отвара»: жидкость остаётся в
///    блюде или впитывается; строка «со сливом» используется только для
///    баланса бульона;
///  * нет строки в источнике → ближайший аналог или обобщённые потери
///    прил. 5; такие значения помечены `// UNVERIFIED` и [NutrientLoss.unverified];
///  * строки «котлеты» и «пассерование» прил. 4 не используются: таких
///    способов нет в перечне приложения.
///
/// БУЛЬОН ([HeatProcess.stock]): считаются нутриенты БУЛЬОНА, а не мяса или
/// овощей. Мясо, кости и овощи из блюда извлекаются, поэтому «потеря»
/// для них = 100 % − доля, перешедшая в воду. Доля взята балансом масс по
/// прил. 4 (что мясо теряет при варке, то переходит в бульон) и помечена
/// UNVERIFIED. Не отделяемые от жидкости продукты (соль, сахар, молоко,
/// жир, мука) остаются в бульоне и считаются как при варке.
abstract final class LossTable {
  /// Потери для группы и способа.
  ///
  /// [HeatProcess.cold] → 0 / 0 / 0. [HeatProcess.legacy] → средние 6 / 12 / 9 %
  /// для любой группы (та же тройка, что [kLegacyRetentionProtein] и др.); движок
  /// для legacy таблицу не использует — там действует тройка блюда.
  static NutrientLoss lossFor(LossGroup group, HeatProcess process) {
    switch (process) {
      case HeatProcess.cold:
        return NutrientLoss.none;
      case HeatProcess.legacy:
        return NutrientLoss.legacyAverage;
      case HeatProcess.boil:
      case HeatProcess.stew:
      case HeatProcess.fry:
      case HeatProcess.bake:
      case HeatProcess.steam:
      case HeatProcess.stock:
        return table[process]![group]!;
    }
  }

  /// Все ячейки таблицы для способов с потерями (6 × 14 = 84).
  static const Map<HeatProcess, Map<LossGroup, NutrientLoss>> table = {
    // ── ВАРКА ── МР 2.3.0419-26, прил. 4 (S1), строки «Варка»;
    // https://rulaws.ru/acts/MR-2.3.0419-26.-2.3.-Gigiena-pitaniya.-Kontrol-za-pischevoy-tsennostyu-gotovyh-blyud-i-ratsionov-pitaniya
    HeatProcess.boil: {
      // S1: варка, мясные — Б 10, Ж 25, У «–» (= 0 по S4).
      LossGroup.meat: NutrientLoss(10, 25, 0, LossSource.mrAppendix4,
          note: 'варка: мясные 10/25/–'),
      // UNVERIFIED: отдельной строки для птицы нет — аналог «мясные» (S1).
      LossGroup.poultry: NutrientLoss(10, 25, 0, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка: мясные»'),
      // S1: варка, рыбные — Б 10, Ж 10, У «–».
      LossGroup.fish: NutrientLoss(10, 10, 0, LossSource.mrAppendix4,
          note: 'варка: рыбные 10/10/–'),
      // UNVERIFIED: строки для яиц нет — обобщённые «животные» 8/25/– (S2).
      LossGroup.egg: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // UNVERIFIED: строки для варки молочных нет — аналог «запекание:
      // молочные» 5/5/5 (S1).
      LossGroup.dairy: NutrientLoss(5, 5, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «запекание: молочные»'),
      // S1: варка растительных без слива — Б 2, Ж 2, крахмал 5.
      LossGroup.grainPasta: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          note: 'варка растительных без слива, крахмал'),
      // S1: как grainPasta (крахмал).
      LossGroup.legumes: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          note: 'варка растительных без слива, крахмал'),
      // S1: как grainPasta (крахмал).
      LossGroup.rootTuber: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          note: 'варка растительных без слива, крахмал'),
      // S1: варка растительных без слива — Б 2, Ж 2, моно- и дисахариды 2.
      LossGroup.vegetable: NutrientLoss(2, 2, 2, LossSource.mrAppendix4,
          note: 'варка растительных без слива, сахара'),
      // S1: как vegetable (моно- и дисахариды).
      LossGroup.fruitBerry: NutrientLoss(2, 2, 2, LossSource.mrAppendix4,
          note: 'варка растительных без слива, сахара'),
      // UNVERIFIED: строки для жиров нет — обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.fatOil: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
      // UNVERIFIED: строки для сахара нет — аналог «варка растительных без
      // слива, сахара» 2/2/2 (S1).
      LossGroup.sugarHoney: NutrientLoss(2, 2, 2, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка растительных», сахара'),
      // S1: как grainPasta (крахмал).
      LossGroup.flourBread: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          note: 'варка растительных без слива, крахмал'),
      // UNVERIFIED: смешанная группа — обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.other: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
    },
    // ── ТУШЕНИЕ ── S1, строки «Тушение» и «Припускание» (URL см. выше).
    HeatProcess.stew: {
      // S1: тушение, мясные — Б 5, Ж 5, У «–».
      LossGroup.meat: NutrientLoss(5, 5, 0, LossSource.mrAppendix4,
          note: 'тушение: мясные 5/5/–'),
      // UNVERIFIED: аналог «тушение: мясные» (S1).
      LossGroup.poultry: NutrientLoss(5, 5, 0, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «тушение: мясные»'),
      // UNVERIFIED: строки нет — аналог «припускание: рыбные» 10/10/– (S1).
      LossGroup.fish: NutrientLoss(10, 10, 0, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: рыбные»'),
      // UNVERIFIED: обобщённые «животные» 8/25/– (S2).
      LossGroup.egg: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // UNVERIFIED: аналог «запекание: молочные» 5/5/5 (S1).
      LossGroup.dairy: NutrientLoss(5, 5, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «запекание: молочные»'),
      // UNVERIFIED: строки «тушение: растительные» нет — аналог
      // «припускание: растительные» 2/10/5/5 (S1).
      LossGroup.grainPasta: NutrientLoss(2, 10, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: растительные»'),
      // UNVERIFIED: как grainPasta.
      LossGroup.legumes: NutrientLoss(2, 10, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: растительные»'),
      // UNVERIFIED: как grainPasta.
      LossGroup.rootTuber: NutrientLoss(2, 10, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: растительные»'),
      // UNVERIFIED: как grainPasta.
      LossGroup.vegetable: NutrientLoss(2, 10, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: растительные»'),
      // UNVERIFIED: как grainPasta.
      LossGroup.fruitBerry: NutrientLoss(2, 10, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: растительные»'),
      // UNVERIFIED: обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.fatOil: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
      // UNVERIFIED: как grainPasta.
      LossGroup.sugarHoney: NutrientLoss(2, 10, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: растительные»'),
      // UNVERIFIED: как grainPasta.
      LossGroup.flourBread: NutrientLoss(2, 10, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «припускание: растительные»'),
      // UNVERIFIED: обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.other: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
    },
    // ── ЖАРКА ── S1, строки «Жарка»; жир для жарки — S3 (URL см. выше).
    HeatProcess.fry: {
      // S1: жарка, мясные — Б 10, Ж 30, У «–».
      LossGroup.meat: NutrientLoss(10, 30, 0, LossSource.mrAppendix4,
          note: 'жарка: мясные 10/30/–'),
      // UNVERIFIED: аналог «жарка: мясные» (S1).
      LossGroup.poultry: NutrientLoss(10, 30, 0, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «жарка: мясные»'),
      // S1: жарка, рыбные — Б 10, Ж 20, У «–».
      LossGroup.fish: NutrientLoss(10, 20, 0, LossSource.mrAppendix4,
          note: 'жарка: рыбные 10/20/–'),
      // UNVERIFIED: обобщённые «животные» 8/25/– (S2).
      LossGroup.egg: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // UNVERIFIED: аналог «запекание: молочные» 5/5/5 (S1).
      LossGroup.dairy: NutrientLoss(5, 5, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «запекание: молочные»'),
      // S1: жарка растительных — Б 5, Ж 10, крахмал 10.
      LossGroup.grainPasta: NutrientLoss(5, 10, 10, LossSource.mrAppendix4,
          note: 'жарка растительных, крахмал'),
      // S1: как grainPasta (крахмал).
      LossGroup.legumes: NutrientLoss(5, 10, 10, LossSource.mrAppendix4,
          note: 'жарка растительных, крахмал'),
      // S1: как grainPasta (крахмал).
      LossGroup.rootTuber: NutrientLoss(5, 10, 10, LossSource.mrAppendix4,
          note: 'жарка растительных, крахмал'),
      // S1: жарка растительных — Б 5, Ж 10, моно- и дисахариды 20.
      LossGroup.vegetable: NutrientLoss(5, 10, 20, LossSource.mrAppendix4,
          note: 'жарка растительных, сахара'),
      // S1: как vegetable (сахара).
      LossGroup.fruitBerry: NutrientLoss(5, 10, 20, LossSource.mrAppendix4,
          note: 'жарка растительных, сахара'),
      // S3: к расчёту принимается 50 % жира для жарки → потери Ж 50 %.
      // UNVERIFIED (Б и У): приняты равными жиру (доля жира, оставшегося в посуде).
      LossGroup.fatOil: NutrientLoss(50, 50, 50, LossSource.mrFryingFat,
          unverified: _proteinCarbs,
          note: 'жир для жарки: учитывается 50 %'),
      // UNVERIFIED: аналог «жарка растительных, сахара» 5/10/20 (S1).
      LossGroup.sugarHoney: NutrientLoss(5, 10, 20, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «жарка растительных», сахара'),
      // S1: как grainPasta (крахмал).
      LossGroup.flourBread: NutrientLoss(5, 10, 10, LossSource.mrAppendix4,
          note: 'жарка растительных, крахмал'),
      // UNVERIFIED: обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.other: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
    },
    // ── ЗАПЕКАНИЕ ── S1 (строка «Запекание: молочные»), остальное — S2.
    HeatProcess.bake: {
      // UNVERIFIED: обобщённые «животные» 8/25/– (S2).
      LossGroup.meat: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // UNVERIFIED: обобщённые «животные» 8/25/– (S2).
      LossGroup.poultry: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // UNVERIFIED: обобщённые «животные» 8/25/– (S2).
      LossGroup.fish: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // UNVERIFIED: обобщённые «животные» 8/25/– (S2).
      LossGroup.egg: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // S1: запекание, молочные — Б 5, Ж 5, углеводы 5.
      LossGroup.dairy: NutrientLoss(5, 5, 5, LossSource.mrAppendix4,
          note: 'запекание: молочные 5/5/5/5'),
      // UNVERIFIED: обобщённые «растительные» 5/6/9 (S2).
      LossGroup.grainPasta: NutrientLoss(5, 6, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: растительные 5/6/9'),
      // UNVERIFIED: обобщённые «растительные» 5/6/9 (S2).
      LossGroup.legumes: NutrientLoss(5, 6, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: растительные 5/6/9'),
      // UNVERIFIED: обобщённые «растительные» 5/6/9 (S2).
      LossGroup.rootTuber: NutrientLoss(5, 6, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: растительные 5/6/9'),
      // UNVERIFIED: обобщённые «растительные» 5/6/9 (S2).
      LossGroup.vegetable: NutrientLoss(5, 6, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: растительные 5/6/9'),
      // UNVERIFIED: обобщённые «растительные» 5/6/9 (S2).
      LossGroup.fruitBerry: NutrientLoss(5, 6, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: растительные 5/6/9'),
      // UNVERIFIED: обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.fatOil: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
      // UNVERIFIED: обобщённые «растительные» 5/6/9 (S2).
      LossGroup.sugarHoney: NutrientLoss(5, 6, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: растительные 5/6/9'),
      // UNVERIFIED: обобщённые «растительные» 5/6/9 (S2).
      LossGroup.flourBread: NutrientLoss(5, 6, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: растительные 5/6/9'),
      // UNVERIFIED: обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.other: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
    },
    // ── НА ПАРУ ── в S1 строки нет: все значения — аналог варки (UNVERIFIED).
    HeatProcess.steam: {
      // UNVERIFIED: аналог «варка: мясные» 10/25/– (S1).
      LossGroup.meat: NutrientLoss(10, 25, 0, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка: мясные»'),
      // UNVERIFIED: аналог «варка: мясные» 10/25/– (S1).
      LossGroup.poultry: NutrientLoss(10, 25, 0, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка: мясные»'),
      // UNVERIFIED: аналог «варка: рыбные» 10/10/– (S1).
      LossGroup.fish: NutrientLoss(10, 10, 0, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка: рыбные»'),
      // UNVERIFIED: обобщённые «животные» 8/25/– (S2).
      LossGroup.egg: NutrientLoss(8, 25, 0, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: животные 8/25/–'),
      // UNVERIFIED: аналог «запекание: молочные» 5/5/5 (S1).
      LossGroup.dairy: NutrientLoss(5, 5, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «запекание: молочные»'),
      // UNVERIFIED: аналог «варка растительных без слива», крахмал (S1).
      LossGroup.grainPasta: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка без слива», крахмал'),
      // UNVERIFIED: как grainPasta.
      LossGroup.legumes: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка без слива», крахмал'),
      // UNVERIFIED: как grainPasta.
      LossGroup.rootTuber: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка без слива», крахмал'),
      // UNVERIFIED: аналог «варка растительных без слива», сахара (S1).
      LossGroup.vegetable: NutrientLoss(2, 2, 2, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка без слива», сахара'),
      // UNVERIFIED: как vegetable.
      LossGroup.fruitBerry: NutrientLoss(2, 2, 2, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка без слива», сахара'),
      // UNVERIFIED: обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.fatOil: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
      // UNVERIFIED: как vegetable.
      LossGroup.sugarHoney: NutrientLoss(2, 2, 2, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка без слива», сахара'),
      // UNVERIFIED: как grainPasta.
      LossGroup.flourBread: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'аналог «варка без слива», крахмал'),
      // UNVERIFIED: обобщённые «в среднем» 6/12/9 (S2).
      LossGroup.other: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'прил. 5: в среднем'),
    },
    // ── БУЛЬОН ── считаются нутриенты БУЛЬОНА, а не мяса/овощей.
    // Потеря = 100 − «перешло в бульон»; «перешло» — баланс масс по S1/S2.
    // Все значения — расчётные, не табличные (UNVERIFIED).
    HeatProcess.stock: {
      // UNVERIFIED: в бульон переходит то, что мясо теряет при варке:
      // 10/25/– (S1) → потери 90/75/100.
      LossGroup.meat: NutrientLoss(90, 75, 100, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 10/25/0 %'),
      // UNVERIFIED: как meat.
      LossGroup.poultry: NutrientLoss(90, 75, 100, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 10/25/0 %'),
      // UNVERIFIED: варка рыбных 10/10/– (S1) → потери 90/90/100.
      LossGroup.fish: NutrientLoss(90, 90, 100, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 10/10/0 %'),
      // UNVERIFIED: «животные» 8/25/– (S2) → потери 92/75/100.
      LossGroup.egg: NutrientLoss(92, 75, 100, LossSource.mrAppendix5,
          unverified: _all, note: 'в бульон переходит 8/25/0 %'),
      // UNVERIFIED: молоко не отделяется от жидкости — как варка 5/5/5.
      LossGroup.dairy: NutrientLoss(5, 5, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'остаётся в бульоне, как варка'),
      // UNVERIFIED: в отвар переходит «со сливом» − «без слива» = 3/3/5
      // (крахмал, S1) → потери 97/97/95.
      LossGroup.grainPasta: NutrientLoss(97, 97, 95, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 3/3/5 %'),
      // UNVERIFIED: как grainPasta.
      LossGroup.legumes: NutrientLoss(97, 97, 95, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 3/3/5 %'),
      // UNVERIFIED: как grainPasta.
      LossGroup.rootTuber: NutrientLoss(97, 97, 95, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 3/3/5 %'),
      // UNVERIFIED: «со сливом» − «без слива» = 3/3/18 (сахара, S1) →
      // потери 97/97/82.
      LossGroup.vegetable: NutrientLoss(97, 97, 82, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 3/3/18 %'),
      // UNVERIFIED: как vegetable.
      LossGroup.fruitBerry: NutrientLoss(97, 97, 82, LossSource.mrAppendix4,
          unverified: _all, note: 'в бульон переходит 3/3/18 %'),
      // UNVERIFIED: жир остаётся в бульоне — «в среднем» 6/12/9 (S2).
      LossGroup.fatOil: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'остаётся в бульоне, в среднем'),
      // UNVERIFIED: сахар растворяется — как варка 2/2/2 (S1).
      LossGroup.sugarHoney: NutrientLoss(2, 2, 2, LossSource.mrAppendix4,
          unverified: _all, note: 'остаётся в бульоне, как варка'),
      // UNVERIFIED: мука не отделяется от жидкости — как варка 2/2/5 (S1).
      LossGroup.flourBread: NutrientLoss(2, 2, 5, LossSource.mrAppendix4,
          unverified: _all, note: 'остаётся в бульоне, как варка'),
      // UNVERIFIED: соль, пряности остаются — «в среднем» 6/12/9 (S2).
      LossGroup.other: NutrientLoss(6, 12, 9, LossSource.mrAppendix5,
          unverified: _all, note: 'остаётся в бульоне, в среднем'),
    },
  };
}

/// Пометка нового расчёта для экрана, бланков и отчётов (решение владельца
/// продукта, задача 2026-11-03): коэффициенты — из открытых источников
/// (S1…S5), а не из текста ГОСТ.
const String kNotGostNotice = 'Пищевая ценность рассчитана по открытым '
    'справочным коэффициентам потерь, не по ГОСТ.';

/// Нутриент строки таблицы потерь.
enum LossNutrient { protein, fat, carbs }

const Set<LossNutrient> _all = {
  LossNutrient.protein,
  LossNutrient.fat,
  LossNutrient.carbs,
};

const Set<LossNutrient> _proteinCarbs = {
  LossNutrient.protein,
  LossNutrient.carbs,
};

/// Потери при тепловой обработке, % от содержания в сырье (0…100).
class NutrientLoss {
  const NutrientLoss(
    this.protein,
    this.fat,
    this.carbs,
    this.source, {
    this.unverified = const <LossNutrient>{},
    this.note = '',
  });

  /// Потери белка, %.
  final double protein;

  /// Потери жира, %.
  final double fat;

  /// Потери углеводов, %.
  final double carbs;

  /// Откуда взято значение (с URL).
  final LossSource source;

  /// Нутриенты, чьё значение не подтверждено таблицей источника
  /// (аналог, обобщённое значение или баланс масс) — список UNVERIFIED.
  final Set<LossNutrient> unverified;

  /// Какая строка источника использована.
  final String note;

  /// Все три числа взяты из таблицы источника напрямую.
  bool get isVerified => unverified.isEmpty;

  /// Без тепловой обработки потерь нет: формула (8) МР при П = 0 (S4).
  static const NutrientLoss none = NutrientLoss(0, 0, 0, LossSource.mrFormula,
      note: 'без тепловой обработки: потерь нет');

  /// Средние потери 6 / 12 / 9 % (S2 «в среднем», S5) — тройка legacy.
  static const NutrientLoss legacyAverage = NutrientLoss(
      6, 12, 9, LossSource.mrAppendix5,
      note: 'прил. 5: в среднем (старый расчёт 0,94 / 0,88 / 0,91)');

  @override
  String toString() =>
      'NutrientLoss($protein/$fat/$carbs, ${source.id}, $note)';
}

/// Источник коэффициента потерь. Идентификаторы S1…S5 — как в
/// `docs/COEFFICIENT_SOURCES.md`.
class LossSource {
  const LossSource({required this.id, required this.title, required this.url});

  final String id;
  final String title;
  final String url;

  static const String _mrUrl =
      'https://rulaws.ru/acts/MR-2.3.0419-26.-2.3.-Gigiena-pitaniya.-Kontrol-za-pischevoy-tsennostyu-gotovyh-blyud-i-ratsionov-pitaniya';

  /// S1 — МР 2.3.0419-26, прил. 4: потери Б/Ж/У по видам тепловой обработки.
  static const LossSource mrAppendix4 = LossSource(
    id: 'S1',
    title: 'МР 2.3.0419-26 «Контроль за пищевой ценностью готовых блюд и '
        'рационов питания», прил. 4 (потери при тепловой обработке)',
    url: _mrUrl,
  );

  /// S2 — МР 2.3.0419-26, прил. 5: обобщённые потери (растительные 5/6/9,
  /// животные 8/25/–, в среднем 6/12/9).
  static const LossSource mrAppendix5 = LossSource(
    id: 'S2',
    title: 'МР 2.3.0419-26, прил. 5 (обобщённые потери при тепловой обработке)',
    url: _mrUrl,
  );

  /// S3 — МР 2.3.0419-26, текст: «при жарке изделий (пассеровании) к расчёту
  /// принимается 50 % от закладываемого по рецептуре жира».
  static const LossSource mrFryingFat = LossSource(
    id: 'S3',
    title: 'МР 2.3.0419-26: при жарке к расчёту принимается 50 % жира '
        'по рецептуре',
    url: _mrUrl,
  );

  /// S4 — МР 2.3.0419-26, формулы (8), (12) и пример расчёта («–» = потерь нет).
  static const LossSource mrFormula = LossSource(
    id: 'S4',
    title: 'МР 2.3.0419-26, формула (8) Сп = Сн × (100 − П) / 100 и пример '
        'расчёта',
    url: _mrUrl,
  );

  /// S5 — Скурихин И. М., 1985: средние потери 6 / 12 / 9 % (источник legacy).
  static const LossSource skurikhin1985 = LossSource(
    id: 'S5',
    title: 'Скурихин И. М. «Вопросы питания», 1985 (средние потери '
        '6/12/9 %)',
    url: 'https://pubmed.ncbi.nlm.nih.gov/4002684/',
  );
}
