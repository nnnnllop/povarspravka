import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../../data/masters_recipes.dart';
import '../providers/dish_provider.dart';
import '../widgets/loss_clarity_hints.dart';
import '../widgets/persistence_error_banner.dart';
import 'recipe_editor_screen.dart';
import 'search_product_modal.dart';

/// Главный экран (аудит P1-7).
///
/// Было: экран открывался рекламным блоком «100% ОФЛАЙН» высотой ~430 dp,
/// под ним горизонтальная карусель рецептур мастеров, потом две плитки-
/// лозунга и в самом низу — сохранённые блюда. То есть главное действие
/// (продолжить начатый расчёт) и главная ценность (моя библиотека) стояли
/// ниже всего, что не помогает повару.
///
/// Стало — правило «сверху вниз по частоте»:
///  1. Активный черновик: одна строка + «Продолжить» (или «Новый расчёт»).
///  2. Мои блюда — библиотека, 1-в-ряд, с выходом и ккал.
///  3. Рецептуры мастеров — сетка по 2 в ряд.
///  4. Нижний док: «Новый расчёт» и «Справочник продуктов».
/// Допущения и форматы — под катом «Как считается», а не на первом экране.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final activeDish = ref.watch(dishProvider);
    final savedDishes = ref.watch(savedDishesProvider);
    final recoveryNotice = ref.watch(storageRecoveryNoticeProvider);
    final compatibilityNotice = ref.watch(storageCompatibilityNoticeProvider);
    final persistenceError = ref.watch(persistenceErrorProvider);
    final savedDishesError = ref.watch(savedDishesErrorProvider);

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 20, color: p.accent),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                'Поварская справка',
                style: AppTypography.title.copyWith(color: p.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Как считается',
            icon: Icon(Icons.info_outline_rounded, color: p.inkSecondary),
            onPressed: () => _showHowItWorks(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (persistenceError != null || savedDishesError != null)
            PersistenceErrorBanner(
              margin: const EdgeInsets.fromLTRB(
                  Space.x4, Space.x2, Space.x4, Space.x2),
              onRetry: () async {
                var ok = true;
                if (ref.read(persistenceErrorProvider) != null) {
                  ok = await ref
                          .read(dishProvider.notifier)
                          .retryPersistence() &&
                      ok;
                }
                if (ref.read(savedDishesErrorProvider) != null) {
                  ok = await ref
                          .read(savedDishesProvider.notifier)
                          .retryLastOperation() &&
                      ok;
                }
                return ok;
              },
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.x4, Space.x2, Space.x4, Space.x6),
              children: [
                if (recoveryNotice != null) ...[
                  _NoticeBanner(
                    bannerKey: const Key('storage-recovery-banner'),
                    icon: Icons.restore_rounded,
                    message: recoveryNotice,
                    onDismiss: () => ref
                        .read(storageRecoveryNoticeProvider.notifier)
                        .state = null,
                  ),
                  const SizedBox(height: Space.x3),
                ],
                if (compatibilityNotice != null) ...[
                  _NoticeBanner(
                    bannerKey: const Key('storage-compatibility-banner'),
                    icon: Icons.info_outline_rounded,
                    message: compatibilityNotice,
                    onDismiss: () => ref
                        .read(storageCompatibilityNoticeProvider.notifier)
                        .state = null,
                  ),
                  const SizedBox(height: Space.x3),
                ],
          _ActiveDraftCard(
            dish: activeDish,
            onOpen: () => _openEditor(context),
            onNew: () => _newCalculation(context, ref),
          ),
          const SizedBox(height: Space.x5),

          // ── Мои блюда ────────────────────────────────────────────────
          _SectionHeader(
            title: 'Мои блюда',
            trailing: savedDishes.isEmpty ? null : '${savedDishes.length}',
          ),
          const SizedBox(height: Space.x2),
          if (savedDishes.isEmpty)
            _EmptyLibrary(palette: p)
          else
            for (final dish in savedDishes) _SavedDishCard(dish: dish),

          const SizedBox(height: Space.x5),

          // ── Рецептуры мастеров ──────────────────────────────────────
          const _SectionHeader(title: 'Рецептуры мастеров'),
          const SizedBox(height: Space.x2),
          _MastersGrid(
            onPick: (recipe) {
              AppHaptics.toggle();
              ref.read(dishProvider.notifier).loadDish(recipe.toDish());
              _openEditor(context);
            },
          ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _HomeDock(
        onNewCalculation: () => _newCalculation(context, ref),
        onCatalog: () => _openCatalog(context),
      ),
    );
  }

  void _openEditor(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
    );
  }

  Future<void> _newCalculation(BuildContext context, WidgetRef ref) async {
    AppHaptics.commit();
    final notifier = ref.read(dishProvider.notifier);
    // Черновик с ингредиентами не теряем: он уходит в библиотеку.
    if (ref.read(dishProvider).ingredients.isNotEmpty) {
      try {
        await notifier.saveCurrentToLibrary();
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить текущий расчёт. Повторите попытку.',
            ),
          ),
        );
        return;
      }
    }
    notifier.createNewDish();
    if (!context.mounted) return;
    _openEditor(context);
  }

  void _openCatalog(BuildContext context) {
    SearchProductModal.show(
      context,
      mode: SearchMode.browseCatalog,
      onAddedFromCatalog: () => _openEditor(context),
    );
  }

  /// Допущения, режимы бланка и форматы экспорта — по требованию.
  /// На первом экране они были справочной стеной, которая отодвигала
  /// сохранённые блюда вниз (аудит P1-7).
  void _showHowItWorks(BuildContext context) {
    final p = Palette.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (ctx) => UncontrolledProviderScope(
        container: container,
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.85,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                Space.x5, 0, Space.x5, Space.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Как считается',
                    style: AppTypography.title.copyWith(color: p.ink)),
                const SizedBox(height: Space.x1),
                Text(
                  'Справочник Скурихина (2002) · Немецкий справочник BLS 4.0. '
                  'Всё считается на устройстве, без интернета.',
                  style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
                ),
                const SizedBox(height: Space.x4),
                _InfoBlock(
                  palette: p,
                  icon: Icons.functions_rounded,
                  title: 'Формула энергетической ценности',
                  body: 'Коэффициенты Этуотера:\n'
                      '• 1 г белков = 4,0 ккал\n'
                      '• 1 г жиров = 9,0 ккал\n'
                      '• 1 г углеводов = 4,0 ккал\n\n'
                      'ЭЦ = Б × 4 + Ж × 9 + У × 4. Расчёт идёт по нутриентам '
                      'после тепловой обработки; вклад алкоголя, пищевых волокон и '
                      'органических кислот формулой не учитывается.',
                ),
                const SizedBox(height: Space.x2),
                _InfoBlock(
                  palette: p,
                  icon: Icons.thermostat_rounded,
                  title: 'Потери при тепловой обработке',
                  body: 'Б, Ж и У каждого продукта уменьшаются на процент потерь '
                      'для его группы и способа обработки (варка, тушение, жарка, '
                      'запекание, на пару, бульон); без тепловой обработки потерь '
                      'нет. Энергия считается от готовых Б/Ж/У. Вес готового блюда '
                      'вводит повар; без него итог дан на всё блюдо. Расчёты, '
                      'сохранённые прежней версией (сохранность 94 / 88 / 91 %), '
                      'открываются с прежними числами.\n\n'
                      'Ключевые допущения модели:\n'
                      '${LossClarityHints.overviewBullets}\n\n'
                      '$kNotGostNotice',
                ),
                const SizedBox(height: Space.x2),
                _InfoBlock(
                  palette: p,
                  icon: Icons.splitscreen_rounded,
                  title: 'Два режима бланка',
                  body: '1. «Бланк с крестом (учебный)» — диагональный крест в '
                      'колонке ккал сырья, калорийность только после т.о.\n'
                      '2. «Подробный расчёт» — калории рассчитаны для каждого продукта.',
                ),
                const SizedBox(height: Space.x2),
                _InfoBlock(
                  palette: p,
                  icon: Icons.file_download_outlined,
                  title: 'Форматы экспорта',
                  body: 'PDF (векторный, идентичен типовому бланку), Word (.docx) '
                      'и Excel (.xlsx) с живыми формулами — файлы сохраняются на '
                      'телефоне и печатаются оттуда.',
                ),
                const SizedBox(height: Space.x2),
                _StorageLocationBlock(palette: p),
                const SizedBox(height: Space.x4),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Понятно'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Информационный баннер хранилища (восстановление из копии или совместимость).
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.bannerKey,
    required this.icon,
    required this.message,
    required this.onDismiss,
  });

  final Key bannerKey;
  final IconData icon;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: bannerKey,
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: Radii.cardAll,
          border: Border.all(color: p.accent, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: p.accent),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.bodySm.copyWith(color: p.ink),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDismiss,
                child: const Text('Понятно'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// IO-07: отображение каталога и файла хранения рецептов в справке.
class _StorageLocationBlock extends ConsumerWidget {
  final Palette palette;

  const _StorageLocationBlock({required this.palette});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = palette;
    final fileName = ref.read(dishStorageRepositoryProvider).storageFileName;
    final dirAsync = ref.watch(storageDirectoryPathProvider);
    return Container(
      key: const ValueKey('storage-location-block'),
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: p.sunken,
        borderRadius: Radii.fieldAll,
        border: Border.all(color: p.borderStatic),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 18, color: p.inkSecondary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'Папка хранения данных',
                  style: AppTypography.label.copyWith(color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          Text(
            'Файл рецептов: $fileName',
            style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
          ),
          const SizedBox(height: Space.x1),
          dirAsync.when(
            loading: () => Text(
              'Определение каталога хранения…',
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
            ),
            error: (_, __) => Text(
              'Каталог хранения недоступен на этой платформе.',
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
            ),
            data: (dirPath) {
              if (dirPath == null || dirPath.trim().isEmpty) {
                return Text(
                  'Каталог хранения недоступен в текущей среде запуска.',
                  style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    dirPath,
                    key: const ValueKey('storage-dir-path'),
                    style: AppTypography.numSm.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: Space.x1),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const ValueKey('copy-storage-dir-btn'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: dirPath));
                        if (!context.mounted) return;
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(
                            content: Text('Путь к папке скопирован'),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, kMinTapTarget),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Скопировать путь'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final Palette palette;
  final IconData icon;
  final String title;
  final String body;

  const _InfoBlock({
    required this.palette,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: p.sunken,
        borderRadius: Radii.fieldAll,
        border: Border.all(color: p.borderStatic),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: p.inkSecondary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(title,
                    style: AppTypography.label.copyWith(color: p.ink)),
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          Text(body,
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary)),
        ],
      ),
    );
  }
}

/// Строка активного расчёта: единственный «продолжить» на экране.
class _ActiveDraftCard extends StatelessWidget {
  final Dish dish;
  final VoidCallback onOpen;
  final VoidCallback onNew;

  const _ActiveDraftCard({
    required this.dish,
    required this.onOpen,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hasContent = dish.ingredients.isNotEmpty;
    // STATE-01: карточка черновика не имеет права ронять домашний экран —
    // невычислимое блюдо показывает прочерки.
    final calc = CalculationEngine.tryCalculate(dish);
    final title = dish.title.trim().isEmpty
        ? (hasContent ? 'Черновик без названия' : 'Новый расчёт')
        : dish.title.trim();

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: hasContent ? p.accent : p.borderStatic),
      ),
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasContent ? 'ПРОДОЛЖИТЬ' : 'НАЧАТЬ',
            style: AppTypography.caption.copyWith(
              color: p.accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: Space.x1),
          Text(
            title,
            style: AppTypography.title.copyWith(color: p.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasContent) ...[
            const SizedBox(height: Space.x1),
            Text(
              calc == null
                  ? '${dish.ingredients.length} инг. · выход — г · — ккал'
                  : '${dish.ingredients.length} инг. · '
                      '${calc.usesLossTable && !calc.hasYield ? 'вес готового блюда не указан' : 'выход ${CalculationEngine.formatGrams(calc.yieldGrams)} г'} · '
                      '${CalculationEngine.formatKcal(calc.cookedKcal)} ккал',
              style: AppTypography.numSm.copyWith(color: p.inkSecondary),
            ),
          ],
          const SizedBox(height: Space.x3),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: hasContent ? onOpen : onNew,
              icon: Icon(
                hasContent ? Icons.edit_note_rounded : Icons.add_rounded,
                size: 20,
              ),
              label: Text(hasContent ? 'Продолжить расчёт' : 'Новый расчёт'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.title.copyWith(color: p.ink),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: AppTypography.numSm.copyWith(color: p.inkMuted),
          ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final Palette palette;

  const _EmptyLibrary({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: palette.borderStatic),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder_open_rounded, size: 20, color: palette.inkMuted),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Text(
              'Здесь появятся сохранённые блюда. Рассчитайте состав и нажмите '
              '«Сохранить» в меню ⋮.',
              style: AppTypography.bodySm.copyWith(color: palette.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка сохранённого блюда: название, выход, ккал, меню действий.
class _SavedDishCard extends ConsumerWidget {
  final Dish dish;

  const _SavedDishCard({required this.dish});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    // STATE-01: карточка сохранённого блюда тоже не имеет права ронять экран.
    final calc = CalculationEngine.tryCalculate(dish);
    final title =
        dish.title.trim().isEmpty ? 'Блюдо без названия' : dish.title.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: Space.x2),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: p.borderStatic),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            ref.read(dishProvider.notifier).loadDish(dish);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.x4, Space.x3, Space.x1, Space.x3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.body.copyWith(
                            color: p.ink, fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        calc == null
                            ? '${dish.ingredients.length} инг. · выход — г · — ккал'
                            : '${dish.ingredients.length} инг. · '
                                '${calc.usesLossTable && !calc.hasYield ? 'вес готового блюда не указан' : 'выход ${CalculationEngine.formatGrams(calc.yieldGrams)} г'} · '
                                '${CalculationEngine.formatKcal(calc.cookedKcal)} ккал',
                        style: AppTypography.numSm.copyWith(color: p.inkSecondary),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Действия с блюдом',
                  icon: Icon(Icons.more_vert_rounded, color: p.inkMuted),
                  onSelected: (value) async {
                    final notifier = ref.read(savedDishesProvider.notifier);
                    try {
                      if (value == 'copy') await notifier.duplicateDish(dish);
                      if (value == 'delete') await notifier.deleteDish(dish.id);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Не удалось: $e')),
                        );
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('Дублировать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Мастера — сетка по 2 в ряд (было: горизонтальная карусель карточек
/// шириной 230 dp, где вторая карточка всегда обрезана).
class _MastersGrid extends StatelessWidget {
  final void Function(MasterRecipe) onPick;

  const _MastersGrid({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      final columns = wide ? 3 : 2;
      const gap = Space.x2;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final recipe in MastersRecipesCatalog.recipes)
            SizedBox(
              width: width,
              child: Container(
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: Radii.cardAll,
                  border: Border.all(color: p.borderStatic),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onPick(recipe),
                    borderRadius: Radii.cardAll,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipe.standardCode,
                            style: AppTypography.caption.copyWith(
                              color: p.inkMuted,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            recipe.name,
                            style: AppTypography.bodySm.copyWith(
                                color: p.ink, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: Space.x1),
                          Text(
                            '${CalculationEngine.formatGrams(recipe.expectedYieldGrams)} г · '
                            '${recipe.ingredients.length} инг.',
                            style: AppTypography.numSm.copyWith(color: p.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Нижний док главного экрана: два главных действия всегда под рукой.
class _HomeDock extends StatelessWidget {
  final VoidCallback onNewCalculation;
  final VoidCallback onCatalog;

  const _HomeDock({
    required this.onNewCalculation,
    required this.onCatalog,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      elevation: 8,
      color: p.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.x4, vertical: Space.x3),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNewCalculation,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Новый расчёт'),
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCatalog,
                  icon: const Icon(Icons.search_rounded, size: 20),
                  label: const Text('Справочник'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
