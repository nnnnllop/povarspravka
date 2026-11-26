import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../data/repositories/backup_service.dart';
import 'app_buttons.dart';
import 'app_sheet.dart';

/// Шторка обмена одним конкретным рецептом (файл `.json` или копирование JSON
/// в буфер обмена — совместимо со шторкой «Восстановить из копии»).
class ShareRecipeSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final title =
        dish.title.trim().isEmpty ? 'Блюдо без названия' : dish.title.trim();
    final customIds = <int>{
      for (final ing in dish.ingredients)
        if (ing.product.source.trim().toLowerCase() == 'custom') ing.product.id,
    };

    return AppSheetScaffold(
      title: 'Поделиться рецептом',
      subtitle: customIds.isEmpty
          ? '«$title» · ${dish.ingredients.length} ингр. Коллега сможет '
              'открыть его через «Настройки и справка → Восстановить из копии».'
          : '«$title» · ${dish.ingredients.length} ингр. (включая своих '
              'продуктов: ${customIds.length}). Импортируется через '
              '«Настройки и справка → Восстановить из копии».',
      showHandle: true,
      maxHeightFactor: 0.8,
      bodyPadding:
          const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const ValueKey('share-recipe-file-btn'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
            ),
            onPressed: () async {
              try {
                await BackupService.shareSingleDishFile(
                  dish,
                  customProducts: customProducts,
                );
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(
                    content: Text(
                      friendlyErrorMessage(
                        e,
                        prefix: 'Не удалось отправить рецепт',
                      ),
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Отправить файлом (.json)'),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            key: const ValueKey('share-recipe-copy-btn'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
            ),
            onPressed: () async {
              final payload = BackupService.encodeSingleDishBackup(
                dish,
                customProducts: customProducts,
              );
              await Clipboard.setData(ClipboardData(text: payload));
              AppHaptics.commit();
              if (!context.mounted) return;
              final messenger = ScaffoldMessenger.maybeOf(context);
              Navigator.pop(context);
              messenger
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('JSON рецепта скопирован в буфер обмена'),
                  ),
                );
            },
            icon: const Icon(Icons.copy_all_rounded, size: 18),
            label: const Text('Скопировать JSON рецепта'),
          ),
        ],
      ),
    );
  }
}
