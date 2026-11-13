/// Способ тепловой обработки блюда.
///
/// Упрощённая модель (решение владельца продукта, задача 2026-11-03):
/// способ влияет ТОЛЬКО на потери белков, жиров и углеводов по группам
/// продуктов (`lib/core/calculation/loss_table.dart`). Масса готового блюда
/// не моделируется: её вводит повар (`Dish.customYieldGrams`). Развариваемость
/// круп, уварка и экстракция удалены вместе с `yield_physics.dart`.
///
/// Имя значения ([name]) — ключ `process` в сохранённом JSON блюда и
/// ингредиента. Значения коэффициентов и их источники — в
/// `docs/COEFFICIENT_SOURCES.md`.
enum HeatProcess {
  /// Старый расчёт: документ без ключа `process` или явный выбор повара.
  ///
  /// Считается РОВНО как до введения технологий: тройка сохранности блюда
  /// (по умолчанию [kLegacyRetentionProtein] / [kLegacyRetentionFat] /
  /// [kLegacyRetentionCarbs]) применяется к суммам сырья, выход — введённый
  /// поваром или сумма нетто. Таблица потерь не используется.
  legacy('старый расчёт (0,94 / 0,88 / 0,91)'),

  /// Без тепловой обработки: потерь нет. Способ нового блюда по умолчанию.
  cold('без обработки'),

  /// Варка (жидкость остаётся в блюде или впитывается).
  boil('варка'),

  /// Тушение.
  stew('тушение'),

  /// Жарка основным способом.
  fry('жарка'),

  /// Запекание.
  bake('запекание'),

  /// Варка на пару.
  steam('на пару'),

  /// Бульон: считаются нутриенты, ПЕРЕШЕДШИЕ В БУЛЬОН, а не оставшиеся в
  /// мясе, костях или овощах (они из блюда извлекаются).
  stock('бульон');

  const HeatProcess(this.label);

  /// Человекочитаемое название способа (UI, бланки, отчёты).
  final String label;

  /// Старый расчёт по одной тройке на всё блюдо.
  bool get isLegacy => this == HeatProcess.legacy;

  /// Способы, которые можно задать отдельному ингредиенту.
  ///
  /// [legacy] — свойство всего документа (одна тройка на блюдо), поэтому у
  /// ингредиента его выбрать нельзя.
  static const List<HeatProcess> ingredientChoices = [
    cold,
    boil,
    stew,
    fry,
    bake,
    steam,
    stock,
  ];

  /// Имена из промежуточной (не выпускавшейся) версии модели технологий.
  ///
  /// Документы с ними читаются без потери данных: `soup` и `grain` были
  /// вариантами варки, `fryMain` — жаркой.
  static const Map<String, HeatProcess> _aliases = {
    'soup': HeatProcess.boil,
    'grain': HeatProcess.boil,
    'fryMain': HeatProcess.fry,
  };

  /// Разбор ключа `process` сохранённого блюда.
  ///
  /// Нет ключа или неизвестное имя → [legacy]: старый документ обязан
  /// считаться прежними числами.
  static HeatProcess fromJsonName(Object? name) {
    if (name is! String) return HeatProcess.legacy;
    for (final p in HeatProcess.values) {
      if (p.name == name) return p;
    }
    return _aliases[name] ?? HeatProcess.legacy;
  }

  /// Разбор ключа `process` ингредиента: `null`, если способ не задан,
  /// неизвестен или равен [legacy] (для ингредиента не допускается).
  static HeatProcess? ingredientFromJsonName(Object? name) {
    if (name is! String) return null;
    final p = fromJsonName(name);
    return p.isLegacy ? null : p;
  }
}

/// Тройка сохранности режима [HeatProcess.legacy]: 94 % белка, 88 % жира,
/// 91 % углеводов, т. е. средние потери 6 / 12 / 9 %.
///
/// Источник: МР 2.3.0419-26 (Роспотребнадзор, 2026), прил. 5 «обобщённые
/// потери», строка «в среднем»: белки 6 %, жиры 12 %, углеводы 9 % —
/// https://rulaws.ru/acts/MR-2.3.0419-26.-2.3.-Gigiena-pitaniya.-Kontrol-za-pischevoy-tsennostyu-gotovyh-blyud-i-ratsionov-pitaniya
/// Исходно — Скурихин И. М., «Вопросы питания», 1985 (PubMed 4002684):
/// https://pubmed.ncbi.nlm.nih.gov/4002684/ ; те же 6 / 12 / 9 % в МУ
/// https://docs.cntd.ru/document/1200091559
const double kLegacyRetentionProtein = 0.94;

/// См. [kLegacyRetentionProtein] (жиры: потери 12 %, тот же источник).
const double kLegacyRetentionFat = 0.88;

/// См. [kLegacyRetentionProtein] (углеводы: потери 9 %, тот же источник).
const double kLegacyRetentionCarbs = 0.91;
