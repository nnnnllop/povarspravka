import 'package:flutter/material.dart';

/// Адаптер раскладки для «нижних» экранов (поиск продукта, детали).
///
/// Тот же виджет используется в двух режимах:
/// * **Bottom sheet** — высота не ограничена сверху (`maxHeight: ∞`) и
///   контент должен прокручиваться сам. Здесь [body] отдаётся как есть,
///   [stickyFooter] идёт следом компактной колонкой, а вся пара заворачивается
///   в [SingleChildScrollView] — поэтому даже при масштабе текста 2.0×
///   ничего не отваливается за край.
/// * **Экран с заданной высотой** (например, `SizedBox.expand` внутри
///   страницы) — контент получает прокрутку, а нижний блок прижат к низу.
///
/// Ни в одном из режимов не бывает «RenderFlex overflowed» и нет
/// бесконечных ограничений внутри `Row`/`Expanded`.
class AdaptiveHost extends StatelessWidget {
  final Widget body;
  final Widget? stickyFooter;

  const AdaptiveHost({
    super.key,
    required this.body,
    this.stickyFooter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          // Шит: тело скроллится само, подвал — сразу под ним. Когда
          // ограничения по высоте нет, отдаём компактную колонку как есть.
          if (stickyFooter == null) return body;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                body,
                stickyFooter!,
              ],
            ),
          );
        }
        return Column(
          children: [
            Expanded(child: body),
            if (stickyFooter != null) stickyFooter!,
          ],
        );
      },
    );
  }
}
