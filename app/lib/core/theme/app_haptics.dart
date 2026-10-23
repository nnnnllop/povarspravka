import 'package:flutter/services.dart';

/// Тактильные токены приложения (аудит §3.6).
///
/// На кухне руки мокрые, в перчатке и с мукой. Тактильный отклик — это не
/// «премиальность», а подтверждение, что нажатие зарегистрировалось, когда
/// смотреть на экран некогда.
class AppHaptics {
  /// Клавиши кейпада, чипы, сегменты, шаги.
  static void key() => _fire(HapticFeedback.selectionClick);

  /// «Добавить в блюдо», сохранение, перестановка, применение параметров.
  static void commit() => _fire(HapticFeedback.lightImpact);

  /// Брутто/Нетто, тумблеры — смена состояния, а не действие.
  static void toggle() => _fire(HapticFeedback.selectionClick);

  /// Ошибка валидации, требующая внимания, но не необратимая.
  static void warn() => _fire(HapticFeedback.mediumImpact);

  /// Необратимое удаление.
  static void error() => _fire(HapticFeedback.heavyImpact);

  /// Глобальный выключатель (например, из настроек).
  static bool enabled = true;

  static void _fire(Future<void> Function() feedback) {
    if (!enabled) return;
    // Платформа может не поддерживать конкретный тип отклика — это не повод
    // падать. Глотаем только ошибки канала, а не всё подряд.
    feedback().catchError((Object _) {});
  }
}
