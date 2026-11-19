import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/backup_service.dart';
import 'app_buttons.dart';

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
    final p = Palette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => ShareRecipeSheet(
        dish: dish,
        customProducts: customProducts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final title =
        dish.title.trim().isEmpty ? 'Блюдо без названия' : dish.title.trim();
    final customIds = <int>{
      for (final ing in dish.ingredients)
        if (ing.product.source.trim().toLowerCase() == 'custom') ing.product.id,
    };

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.x5, 0, Space.x5, Space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Поделиться рецептом',
              style: AppTypography.title.copyWith(color: p.ink),
            ),
            const SizedBox(height: Space.x1),
            Text(
              customIds.isEmpty
                  ? '«$title» · ${dish.ingredients.length} ингр. Коллега сможет '
                      'открыть его через «Как считается → Восстановить из копии».'
                  : '«$title» · ${dish.ingredients.length} ингр. (включая своих '
                      'продуктов: ${customIds.length}). Импортируется через '
                      '«Как считается → Восстановить из копии».',
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
            ),
            const SizedBox(height: Space.x4),
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
      ),
    );
  }
}
