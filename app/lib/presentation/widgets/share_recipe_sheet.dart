import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/backup_service.dart';
import 'app_buttons.dart';
import 'app_sheet.dart';

/// Шторка обмена одним конкретным рецептом (файл `.json` или копирование JSON
/// в буфер обмена — совместимо со шторкой «Восстановить из копии»).
class ShareRecipeSheet extends StatefulWidget {
  final Dish dish;
  final List<Product> customProducts;

  const ShareRecipeSheet({
    super.key,
    required this.dish,
    required this.customProducts,
  });

  static Future<void> show(
    BuildContext context, {
    required Dish dish,
    required List<Product> customProducts,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareRecipeSheet(
        dish: dish,
        customProducts: customProducts,
      ),
    );
  }

  @override
  State<ShareRecipeSheet> createState() => _ShareRecipeSheetState();
}

class _ShareRecipeSheetState extends State<ShareRecipeSheet> {
  String? _errorText;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final title = widget.dish.title.trim().isEmpty
        ? 'Блюдо без названия'
        : widget.dish.title.trim();
    final customIds = <int>{
      for (final ing in widget.dish.ingredients)
        if (ing.product.source.trim().toLowerCase() == 'custom') ing.product.id,
    };

    return AppSheetScaffold(
      title: 'Поделиться рецептом',
      subtitle:
          '«$title» · ${pluralIngredients(widget.dish.ingredients.length)}',
      showHandle: true,
      showClose: true,
      maxHeightFactor: 0.8,
      noticeText: _errorText,
      noticeIsError: true,
      bodyPadding:
          const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            customIds.isEmpty
                ? 'Коллега сможет открыть рецепт через «Настройки и справка → Восстановить из копии».'
                : 'В составе есть свои продукты (${customIds.length}) — они тоже войдут в файл. Импорт: «Настройки и справка → Восстановить из копии».',
            style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
          ),
          const SizedBox(height: Space.x3),
          FilledButton.icon(
            key: const ValueKey('share-recipe-file-btn'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
            ),
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _errorText = null;
                    });
                    try {
                      await BackupService.shareSingleDishFile(
                        widget.dish,
                        customProducts: widget.customProducts,
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _busy = false;
                        _errorText = friendlyErrorMessage(
                          e,
                          prefix: 'Не удалось отправить рецепт',
                        );
                      });
                    }
                  },
            icon: const Icon(Icons.ios_share_rounded, size: IconSizes.btn),
            label: const Text('Отправить файлом (.json)'),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            key: const ValueKey('share-recipe-copy-btn'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
            ),
            onPressed: _busy
                ? null
                : () async {
                    final payload = BackupService.encodeSingleDishBackup(
                      widget.dish,
                      customProducts: widget.customProducts,
                    );
                    await Clipboard.setData(ClipboardData(text: payload));
                    AppHaptics.commit();
                    if (!mounted) return;
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    Navigator.pop(context);
                    messenger
                      ?..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content:
                              Text('JSON рецепта скопирован в буфер обмена'),
                        ),
                      );
                  },
            icon: const Icon(Icons.copy_all_rounded, size: IconSizes.btn),
            label: const Text('Скопировать JSON рецепта'),
          ),
        ],
      ),
    );
  }
}
