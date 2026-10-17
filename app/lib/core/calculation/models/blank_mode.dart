enum BlankMode {
  /// Режим 1: «Как на фото» — диагональный крест / черта в колонке ккал сырья;
  /// калорийность рассчитывается только в строке «После тепловой обработки».
  photoCross,

  /// Режим 2: «Подробный» — калорийность рассчитывается построчно для каждого сырья,
  /// суммируется в «Итого», затем рассчитывается «После т.о.».
  detailed;

  String get displayName {
    switch (this) {
      case BlankMode.photoCross:
        return 'Бланк с крестом (учебный)';
      case BlankMode.detailed:
        return 'Подробный расчёт (ккал по каждому продукту)';
    }
  }

  String get shortName {
    switch (this) {
      case BlankMode.photoCross:
        return 'Бланк с крестом (учебный)';
      case BlankMode.detailed:
        return 'Подробный расчёт';
    }
  }
}
