/// Группа продукта для таблицы потерь (`lib/core/calculation/loss_table.dart`).
///
/// 14 групп из решения владельца продукта (задача 2026-11-03). Группа
/// определяется по `group_id` справочника (`FoodClassifier`); повар может
/// сменить её у ингредиента вручную (`Ingredient.groupOverride`).
///
/// Имя значения ([name]) — ключ `group` в сохранённом JSON ингредиента.
///
/// Не путать с `FoodGroup` из `product_repository.dart` — это группа
/// справочника (`food_group` в `reference.db`, 32 записи), а [LossGroup] —
/// группа таблицы потерь, в которую она отображается.
enum LossGroup {
  meat('мясо'),
  poultry('птица'),
  fish('рыба'),
  egg('яйцо'),
  dairy('молочное'),
  grainPasta('крупы и макароны'),
  legumes('бобовые'),
  rootTuber('корнеплоды и картофель'),
  vegetable('овощи'),
  fruitBerry('фрукты и ягоды'),
  fatOil('жиры и масла'),
  sugarHoney('сахар и мёд'),
  flourBread('мука и хлеб'),
  other('прочее');

  const LossGroup(this.label);

  /// Название группы для UI и отчётов.
  final String label;

  /// Разбор ключа `group` из JSON: `null` для отсутствующего или
  /// неизвестного имени (тогда группа берётся из классификатора).
  static LossGroup? fromJsonName(Object? name) {
    if (name is! String) return null;
    for (final g in LossGroup.values) {
      if (g.name == name) return g;
    }
    return null;
  }
}
