import '../../core/calculation/models/heat_process.dart';
import '../../core/calculation/models/loss_group.dart';

/// Ясные методические пояснения для повара по таблице потерь (A3-SRC-01/02)
/// без изменения числовых коэффициентов в `LossTable`.
class LossClarityHints {
  const LossClarityHints._();

  static const Set<LossGroup> _plantGroups = {
    LossGroup.grainPasta,
    LossGroup.legumes,
    LossGroup.rootTuber,
    LossGroup.vegetable,
    LossGroup.fruitBerry,
  };

  static const String boilPlantNote =
      'Варка растительных продуктов (овощи, корнеплоды, бобовые, крупы, '
      'фрукты) считается без слива отвара. При сливе отвара фактические '
      'потери нутриентов выше.';

  static const String stockTransferNote =
      'Бульон — оценочный переход нутриентов в жидкость (гуща не '
      'учитывается). Если мясо и овощи остаются в тарелке (суп), '
      'выберите «варка».';

  static const String fryFatNote =
      'При жарке учитывается 50 % добавленного жира (МР 2.3.0419-26): '
      'в таблице потерь для группы «жиры и масла» указана потеря 50 %.';

  static const String overviewBullets =
      '• $boilPlantNote\n'
      '• $stockTransferNote\n'
      '• $fryFatNote';

  /// Пояснение для выбранного способа тепловой обработки блюда (или `null`).
  static String? forDishProcess(HeatProcess process) {
    return switch (process) {
      HeatProcess.boil => boilPlantNote,
      HeatProcess.stock => stockTransferNote,
      HeatProcess.fry => fryFatNote,
      HeatProcess.legacy ||
      HeatProcess.cold ||
      HeatProcess.stew ||
      HeatProcess.bake ||
      HeatProcess.steam =>
        null,
    };
  }

  /// Контекстное пояснение для конкретного сочетания группы и способа.
  static String? forIngredient({
    required LossGroup group,
    required HeatProcess process,
  }) {
    if (process == HeatProcess.stock) return stockTransferNote;
    if (process == HeatProcess.boil && _plantGroups.contains(group)) {
      return boilPlantNote;
    }
    if (process == HeatProcess.fry && group == LossGroup.fatOil) {
      return fryFatNote;
    }
    return null;
  }

  /// Собирает уникальные релевантные пояснения для набора строк расчёта.
  static List<String> forLines(
    Iterable<({LossGroup group, HeatProcess process})> lines,
  ) {
    final notes = <String>[];
    for (final line in lines) {
      final note = forIngredient(group: line.group, process: line.process);
      if (note != null && !notes.contains(note)) {
        notes.add(note);
      }
    }
    return notes;
  }
}
