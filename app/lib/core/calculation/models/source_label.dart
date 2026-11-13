/// Единая точка подписи источника справочника (дефект D17).
///
/// Раньше подпись источника жила в ДВУХ местах: `Product.sourceLabel`
/// (строкой в модели) и `SourceBadge.labelFor` (switch в виджете). Они
/// разъехались: `sourceLabel` считал всё, что не «Скурихин» и не
/// «supplement», — «BLS», включая устаревший `usda`, а `labelFor` отдавал
/// для `usda` сырой код источника.
///
/// Теперь таблица одна — здесь. Модель (`Product.sourceLabel`) берёт пустоту
/// для неизвестного источника, а значок (`SourceBadge.labelFor`) —
/// сам код: на бейдже пустая подпись выглядела бы как дефект вёрстки.
class SourceLabel {
  const SourceLabel._();

  /// Код источника в БД -> подпись для пользователя.
  static const Map<String, String> labels = {
    'skurikhin': 'Скурихин',
    'bls': 'BLS',
    // Пряности и питьевая вода, которых нет ни в книге, ни в BLS (дефект
    // D3): подписываются «Дополнено», иначе пользователь решил бы, что
    // сода и корица пришли из Bundeslebensmittelschlüssel.
    'supplement': 'Дополнено',
    // Устаревшее имя источника: справочник USDA заменён на BLS 4.0, но
    // сохранённые рецепты могут нести старый код.
    'usda': 'BLS',
  };

  /// Подпись источника или `fallback`, если источник неизвестен.
  static String of(String source, {String fallback = ''}) {
    return labels[source.trim().toLowerCase()] ?? fallback;
  }
}
