import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/backup_service.dart';
import '../../data/repositories/custom_products_repository.dart';
import '../providers/dish_provider.dart';
import '../providers/search_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_sheet.dart';
import '../widgets/batch_export_sheet.dart';
import '../widgets/dish_comparison_sheet.dart';
import '../widgets/instrument_widgets.dart';
import '../widgets/loss_clarity_hints.dart';
import '../widgets/menu_builder_sheet.dart';
import '../widgets/persistence_error_banner.dart';
import '../widgets/share_recipe_sheet.dart';
import 'recipe_editor_screen.dart';
import 'search_product_modal.dart';

/// Главный экран: активный черновик, библиотека «Мои блюда» и нижний док
/// («Новый расчёт» и «Справочник»). Допущения вынесены в шторку «Как считается».
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum _LibrarySort {
  newest('Недавно изменённые'),
  title('По названию (А–Я)'),
  kcalPer100g('По ккал на 100 г');

  final String label;
  const _LibrarySort(this.label);
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _librarySearchCtrl = TextEditingController();
  bool _librarySearchOpen = false;
  String _libraryQuery = '';
  String? _selectedCategory;
  _LibrarySort _librarySort = _LibrarySort.newest;
  bool _selectionMode = false;
  final Set<String> _selectedDishIds = <String>{};

  void _toggleDishSelection(String dishId) {
    AppHaptics.toggle();
    setState(() {
      _selectionMode = true;
      if (!_selectedDishIds.add(dishId)) {
        _selectedDishIds.remove(dishId);
      }
    });
  }

  void _enterSelectionMode() {
    AppHaptics.toggle();
    setState(() {
      _selectionMode = true;
      _selectedDishIds.clear();
    });
  }

  void _startSelection(String dishId) {
    AppHaptics.toggle();
    setState(() {
      _selectionMode = true;
      _selectedDishIds.add(dishId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedDishIds.clear();
    });
  }

  @override
  void dispose() {
    _librarySearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final activeDish = ref.watch(dishProvider);
    final savedDishes = ref.watch(savedDishesProvider);
    final recoveryNotice = ref.watch(storageRecoveryNoticeProvider);
    final compatibilityNotice = ref.watch(storageCompatibilityNoticeProvider);
    final persistenceError = ref.watch(persistenceErrorProvider);
    final savedDishesError = ref.watch(savedDishesErrorProvider);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Space.gutter(width);
    final listHPad = math.max(gutter, (width - Space.maxWidth) / 2);
    final hasActiveDraft =
        activeDish.ingredients.isNotEmpty || activeDish.title.trim().isNotEmpty;

    final usedCategoryIds = <String>{
      for (final d in savedDishes)
        if (d.category != null) d.category!,
    };
    final usedCategories = [
      for (final item in DishCategories.all)
        if (usedCategoryIds.contains(item.id)) item,
    ];
    final activeCategoryFilter =
        (_selectedCategory != null && usedCategoryIds.contains(_selectedCategory))
            ? _selectedCategory
            : null;

    final showSearchToggle = savedDishes.length >= 2;
    final showSearchInput = _librarySearchOpen ||
        savedDishes.length >= 6 ||
        _libraryQuery.isNotEmpty;
    final normQuery = CustomProductsRepository.normalizeText(_libraryQuery);
    final filteredDishes = savedDishes.where((d) {
      if (activeCategoryFilter != null && d.category != activeCategoryFilter) {
        return false;
      }
      if (normQuery.isEmpty) return true;
      final t = d.title.trim().isEmpty
          ? 'блюдо без названия'
          : CustomProductsRepository.normalizeText(d.title);
      return t.contains(normQuery);
    }).toList();

    if (_librarySort == _LibrarySort.title) {
      filteredDishes.sort((a, b) {
        final at = a.title.trim().isEmpty
            ? 'блюдо без названия'
            : a.title.trim().toLowerCase();
        final bt = b.title.trim().isEmpty
            ? 'блюдо без названия'
            : b.title.trim().toLowerCase();
        return at.compareTo(bt);
      });
    } else if (_librarySort == _LibrarySort.kcalPer100g) {
      final kcalById = <String, double>{
        for (final d in filteredDishes)
          d.id: (() {
            final c = CalculationEngine.tryCalculate(d);
            return (c != null && c.hasYield) ? c.per100gKcal : -1.0;
          })(),
      };
      filteredDishes.sort((a, b) {
        final cmp = (kcalById[b.id] ?? -1.0).compareTo(kcalById[a.id] ?? -1.0);
        if (cmp != 0) return cmp;
        return a.title.trim().toLowerCase().compareTo(
              b.title.trim().toLowerCase(),
            );
      });
    } else {
      filteredDishes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    final liveIds = {for (final d in savedDishes) d.id};
    _selectedDishIds.removeWhere((id) => !liveIds.contains(id));
    final selectedDishes = [
      for (final d in savedDishes)
        if (_selectedDishIds.contains(d.id)) d,
    ];
    final isSelecting = _selectionMode || selectedDishes.isNotEmpty;
    final visibleIds = {for (final d in filteredDishes) d.id};
    final hiddenSelectedCount =
        selectedDishes.where((d) => !visibleIds.contains(d.id)).length;
    final allVisibleSelected = visibleIds.isNotEmpty &&
        visibleIds.every(_selectedDishIds.contains);
    final compactSelectionActions = AppLayout.isNarrow(width) ||
        AppLayout.isLargeText(MediaQuery.textScalerOf(context).scale(1.0));

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isSelecting) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        appBar: isSelecting
            ? AppBar(
                toolbarHeight: kToolbarHeight,
                backgroundColor: p.surface,
                foregroundColor: p.ink,
                shape: Border(bottom: BorderSide(color: p.divider)),
                leading: IconButton(
                  key: const ValueKey('selection-close-btn'),
                  tooltip: 'Отменить выбор',
                  icon: Icon(Icons.close_rounded, color: p.ink),
                  onPressed: _exitSelectionMode,
                ),
                title: Semantics(
                  liveRegion: true,
                  child: Text(
                    hiddenSelectedCount > 0
                        ? 'Выбрано ${selectedDishes.length} · скрыто $hiddenSelectedCount'
                        : 'Выбрано ${selectedDishes.length}',
                    style: AppTypography.headline.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                actions: [
                  if (selectedDishes.isNotEmpty)
                    compactSelectionActions
                        ? IconButton(
                            key: const ValueKey('selection-clear-all-btn'),
                            tooltip: 'Снять всё',
                            icon: Icon(
                              Icons.layers_clear_rounded,
                              color: p.inkSecondary,
                            ),
                            onPressed: () {
                              AppHaptics.toggle();
                              setState(() => _selectedDishIds.clear());
                            },
                          )
                        : TextButton(
                            key: const ValueKey('selection-clear-all-btn'),
                            onPressed: () {
                              AppHaptics.toggle();
                              setState(() => _selectedDishIds.clear());
                            },
                            child: const Text('Снять всё'),
                          ),
                  if (!allVisibleSelected && visibleIds.isNotEmpty)
                    IconButton(
                      key: const ValueKey('selection-toggle-all-btn'),
                      tooltip: 'Выбрать все видимые',
                      icon: Icon(Icons.select_all_rounded, color: p.accent),
                      onPressed: () {
                        AppHaptics.toggle();
                        setState(() {
                          _selectedDishIds.addAll(visibleIds);
                        });
                      },
                    ),
                ],
              )
            : AppBar(
                toolbarHeight: kToolbarHeight,
                title: Row(
                  children: [
                    const AppScaleGlyph(size: 22),
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
                  if (savedDishes.length >= 2)
                    IconButton(
                      key: const ValueKey('home-select-mode-btn'),
                      tooltip: 'Выбрать блюда',
                      icon: Icon(Icons.checklist_rounded,
                          color: p.inkSecondary),
                      onPressed: _enterSelectionMode,
                    ),
                  IconButton(
                    tooltip: 'Настройки и справка',
                    icon: Icon(Icons.tune_rounded, color: p.inkSecondary),
                    onPressed: () => _showHowItWorks(context),
                  ),
                ],
              ),
      body: Column(
        children: [
          if (persistenceError != null || savedDishesError != null)
            AppContentFrame(
              child: PersistenceErrorBanner(
                margin: EdgeInsets.fromLTRB(
                    gutter, Space.x2, gutter, Space.x2),
                onRetry: () async {
                  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
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
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  listHPad, Space.x2, listHPad, Space.x6),
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
                if (hasActiveDraft) ...[
                  IgnorePointer(
                    ignoring: isSelecting,
                    child: AnimatedOpacity(
                      duration: Motion.fast,
                      opacity: isSelecting ? 0.45 : 1.0,
                      child: _ActiveDraftCard(
                        dish: activeDish,
                        onOpen: () => _openEditor(context),
                        onNew: () => _newCalculation(context, ref),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.x4),
                ],

                // ── Мои блюда ────────────────────────────────────────────────
                _SectionHeader(
                  title: 'Мои блюда',
                  trailing: savedDishes.isEmpty
                      ? null
                      : (filteredDishes.length == savedDishes.length
                          ? '${savedDishes.length}'
                          : '${filteredDishes.length} из ${savedDishes.length}'),
                  onSearchToggle: showSearchToggle && savedDishes.length < 6
                      ? () {
                          setState(() {
                            _librarySearchOpen = !_librarySearchOpen;
                            if (!_librarySearchOpen) {
                              _librarySearchCtrl.clear();
                              _libraryQuery = '';
                            }
                          });
                        }
                      : null,
                  searchActive: _librarySearchOpen,
                  sortControl: savedDishes.length >= 2
                      ? PopupMenuButton<_LibrarySort>(
                          key: const ValueKey('home-library-sort-btn'),
                          tooltip: 'Сортировка блюд',
                          initialValue: _librarySort,
                          onSelected: (sort) {
                            AppHaptics.toggle();
                            setState(() => _librarySort = sort);
                          },
                          icon: Icon(
                            Icons.sort_rounded,
                            size: 20,
                            color: _librarySort != _LibrarySort.newest
                                ? p.accent
                                : p.inkSecondary,
                          ),
                          itemBuilder: (_) => [
                            for (final option in _LibrarySort.values)
                              PopupMenuItem<_LibrarySort>(
                                value: option,
                                child: Row(
                                  children: [
                                    Icon(
                                      option == _librarySort
                                          ? Icons.check_rounded
                                          : Icons.circle,
                                      size: option == _librarySort ? 18 : 0,
                                      color: p.accent,
                                    ),
                                    if (option == _librarySort)
                                      const SizedBox(width: Space.x2),
                                    Expanded(child: Text(option.label)),
                                  ],
                                ),
                              ),
                          ],
                        )
                      : null,
                ),
                if (usedCategories.isNotEmpty) ...[
                  const SizedBox(height: Space.x2),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          key: const ValueKey('home-cat-all'),
                          label: const Text('Все'),
                          selected: activeCategoryFilter == null,
                          showCheckmark: false,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) {
                            AppHaptics.toggle();
                            setState(() => _selectedCategory = null);
                          },
                        ),
                        for (final cat in usedCategories) ...[
                          const SizedBox(width: Space.x2),
                          ChoiceChip(
                            key: ValueKey('home-cat-${cat.id}'),
                            label: Text(cat.label),
                            selected: activeCategoryFilter == cat.id,
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: (_) {
                              AppHaptics.toggle();
                              setState(() {
                                _selectedCategory =
                                    activeCategoryFilter == cat.id
                                        ? null
                                        : cat.id;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (showSearchInput && savedDishes.isNotEmpty) ...[
                  const SizedBox(height: Space.x2),
                  TextField(
                    key: const ValueKey('home-library-search'),
                    controller: _librarySearchCtrl,
                    onChanged: (v) => setState(() => _libraryQuery = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Поиск по моим блюдам…',
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20, color: p.inkMuted),
                      suffixIcon: _libraryQuery.isNotEmpty
                          ? IconButton(
                              tooltip: 'Очистить поиск',
                              icon: Icon(Icons.close_rounded,
                                  size: 18, color: p.inkMuted),
                              onPressed: () {
                                _librarySearchCtrl.clear();
                                setState(() => _libraryQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ],
                const SizedBox(height: Space.x2),
                if (savedDishes.isEmpty)
                  _EmptyLibrary(palette: p)
                else if (filteredDishes.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(Space.x4),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: Radii.cardAll,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _libraryQuery.trim().isNotEmpty
                                ? 'По запросу «${_libraryQuery.trim()}» блюд не найдено'
                                : 'В выбранной категории блюд не найдено',
                            style: AppTypography.bodySm
                                .copyWith(color: p.inkSecondary),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _librarySearchCtrl.clear();
                            setState(() {
                              _libraryQuery = '';
                              _selectedCategory = null;
                            });
                          },
                          child: const Text('Сбросить'),
                        ),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < filteredDishes.length; i++)
                    _SavedDishCard(
                      dish: filteredDishes[i],
                      isFirst: i == 0,
                      isLast: i == filteredDishes.length - 1,
                      isSelecting: isSelecting,
                      isSelected:
                          _selectedDishIds.contains(filteredDishes[i].id),
                      onToggleSelect: () =>
                          _toggleDishSelection(filteredDishes[i].id),
                      onStartSelect: () =>
                          _startSelection(filteredDishes[i].id),
                    ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isSelecting
          ? _SelectionDock(
              selectedCount: selectedDishes.length,
              onCompare: selectedDishes.length == 2
                  ? () => DishComparisonSheet.show(
                        context,
                        first: selectedDishes[0],
                        second: selectedDishes[1],
                      )
                  : null,
              onMenu: selectedDishes.isNotEmpty
                  ? () => MenuBuilderSheet.show(
                        context,
                        dishes: selectedDishes,
                      )
                  : null,
              onExport: selectedDishes.isNotEmpty
                  ? () => BatchExportSheet.show(
                        context,
                        dishes: selectedDishes,
                      )
                  : null,
            )
          : _HomeDock(
              onNewCalculation: () => _newCalculation(context, ref),
              onCatalog: () => _openCatalog(context),
            ),
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
    if (notifier.isDirty) {
      final ok = await _confirmReplaceDirtyDraft(context, ref);
      if (!ok || !context.mounted) return;
    } else if (ref.read(dishProvider).ingredients.isNotEmpty) {
      // Чистый активный черновик с составом фиксируем в библиотеке перед новым.
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
    final container = ProviderScope.containerOf(context, listen: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (sheetCtx, sheetRef, _) {
            final p = Palette.of(sheetCtx);
            final settings = sheetRef.watch(appSettingsProvider);
            final savedDishes = sheetRef.watch(savedDishesProvider);
            final customProducts = sheetRef.watch(customProductsProvider);
            final favoriteProducts = sheetRef.watch(favoriteProductsProvider);
            final savedCount = savedDishes.length;
            final customCount = customProducts.length;
            final favoriteCount = favoriteProducts.length;
            final hasBackupData =
                savedCount > 0 || customCount > 0 || favoriteCount > 0;

            return AppSheetScaffold(
              title: 'Настройки и справка',
              subtitle: 'Версия ${BackupService.appVersionLabel}',
              showHandle: true,
              maxHeightFactor: 0.9,
              bodyPadding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x3,
                Space.x4,
                Space.x4,
              ),
              footer: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: const Text('Понятно'),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    Row(
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          size: 18,
                          color: p.accent,
                        ),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Text(
                            'Оформление и отклик',
                            style:
                                AppTypography.headline.copyWith(color: p.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                    Builder(
                      builder: (segCtx) {
                        final mq = MediaQuery.of(segCtx);
                        final wrapThemeChips = AppLayout.isNarrow(mq.size.width) ||
                            AppLayout.isLargeText(mq.textScaler.scale(1.0));
                        void selectTheme(ThemeMode mode) {
                          AppHaptics.toggle();
                          sheetRef
                              .read(appSettingsProvider.notifier)
                              .setThemeMode(mode);
                        }

                        if (wrapThemeChips) {
                          return Wrap(
                            key: const ValueKey('theme-mode-segmented'),
                            spacing: Space.x2,
                            runSpacing: Space.x2,
                            children: [
                              for (final (mode, label) in const [
                                (ThemeMode.system, 'Авто'),
                                (ThemeMode.light, 'Светлая'),
                                (ThemeMode.dark, 'Тёмная'),
                              ])
                                ChoiceChip(
                                  label: Text(label),
                                  selected: settings.themeMode == mode,
                                  showCheckmark: false,
                                  onSelected: (_) => selectTheme(mode),
                                ),
                            ],
                          );
                        }

                        return SegmentedButton<ThemeMode>(
                          key: const ValueKey('theme-mode-segmented'),
                          showSelectedIcon: false,
                          style: AppSegmentedStyle.of(p, compact: true),
                          segments: const [
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.system,
                              label: Text(
                                'Авто',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.light,
                              label: Text(
                                'Светлая',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.dark,
                              label: Text(
                                'Тёмная',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (sel) {
                            if (sel.isEmpty) return;
                            selectTheme(sel.first);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: Space.x2),
                    SwitchListTile.adaptive(
                      key: const ValueKey('haptics-switch'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.hapticsEnabled,
                      title: Text(
                        'Тактильный отклик',
                        style: AppTypography.body.copyWith(color: p.ink),
                      ),
                      subtitle: Text(
                        'Лёгкая вибрация при выборе продуктов и нажатии кнопок',
                        style: AppTypography.bodySm
                            .copyWith(color: p.inkSecondary),
                      ),
                      onChanged: (enabled) async {
                        await sheetRef
                            .read(appSettingsProvider.notifier)
                            .setHapticsEnabled(enabled);
                        if (enabled) AppHaptics.toggle();
                      },
                    ),
                    Divider(color: p.divider, height: Space.x5),
                    Row(
                      children: [
                        Icon(
                          Icons.backup_outlined,
                          size: 18,
                          color: p.accent,
                        ),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Text(
                            'Резервная копия данных',
                            style:
                                AppTypography.headline.copyWith(color: p.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.x1),
                    Text(
                      favoriteCount > 0
                          ? 'Блюд: $savedCount · Своих: $customCount · Избранных: $favoriteCount'
                          : 'Блюд в библиотеке: $savedCount · Своих продуктов: $customCount',
                      key: const ValueKey('backup-counts-text'),
                      style:
                          AppTypography.bodySm.copyWith(color: p.inkSecondary),
                    ),
                    const SizedBox(height: Space.x3),
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x2,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('backup-share-btn'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, kMinTapTarget),
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          onPressed: !hasBackupData
                              ? null
                              : () async {
                                  try {
                                    await BackupService.shareBackupFile(
                                      savedDishes: savedDishes,
                                      customProducts: customProducts,
                                      favoriteProducts: favoriteProducts,
                                    );
                                  } catch (e) {
                                    if (!sheetCtx.mounted) return;
                                    ScaffoldMessenger.maybeOf(sheetCtx)
                                        ?.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          friendlyErrorMessage(
                                            e,
                                            prefix:
                                                'Не удалось выгрузить копию',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('Поделиться файлом'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('backup-copy-btn'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, kMinTapTarget),
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          onPressed: !hasBackupData
                              ? null
                              : () async {
                                  final json = BackupService.encodeBackup(
                                    savedDishes: savedDishes,
                                    customProducts: customProducts,
                                    favoriteProducts: favoriteProducts,
                                  );
                                  await Clipboard.setData(
                                    ClipboardData(text: json),
                                  );
                                  AppHaptics.commit();
                                  if (!sheetCtx.mounted) return;
                                  ScaffoldMessenger.maybeOf(sheetCtx)
                                      ?.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'JSON резервной копии скопирован',
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.copy_all_rounded, size: 18),
                          label: const Text('Скопировать JSON'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('backup-restore-btn'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, kMinTapTarget),
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            if (!context.mounted) return;
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              showDragHandle: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius: Radii.sheetTop,
                              ),
                              builder: (restoreCtx) =>
                                  UncontrolledProviderScope(
                                container: container,
                                child: const _RestoreBackupSheet(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.restore_rounded, size: 18),
                          label: const Text('Восстановить из копии'),
                        ),
                      ],
                    ),
                    Divider(color: p.divider, height: Space.x5),
                    Text(
                      'Как считается · Справочники',
                      style: AppTypography.headline.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: Space.x1),
                    Text(
                      'Справочник Скурихина (2002) · Немецкий справочник BLS 4.0. '
                      'Всё считается на устройстве, без интернета.',
                      style:
                          AppTypography.bodySm.copyWith(color: p.inkSecondary),
                    ),
                    Divider(color: p.divider, height: Space.x5),
                    _InfoSection(
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
                    Divider(color: p.divider, height: Space.x5),
                    _InfoSection(
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
                    Divider(color: p.divider, height: Space.x5),
                    _InfoSection(
                      palette: p,
                      icon: Icons.splitscreen_rounded,
                      title: 'Два режима бланка',
                      body: '1. «Бланк с крестом (учебный)» — диагональный крест в '
                          'колонке ккал сырья, калорийность только после готовки.\n'
                          '2. «Подробный расчёт» — калории рассчитаны для каждого продукта.',
                    ),
                    Divider(color: p.divider, height: Space.x5),
                    _InfoSection(
                      palette: p,
                      icon: Icons.file_download_outlined,
                      title: 'Форматы экспорта',
                      body: 'PDF (векторный, идентичен типовому бланку), Word (.docx) '
                          'и Excel (.xlsx) с живыми формулами — файлы сохраняются на '
                          'телефоне и печатаются оттуда.',
                    ),
                    Divider(color: p.divider, height: Space.x5),
                    Theme(
                      data: Theme.of(sheetCtx)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: const ValueKey('tech-info-expansion'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding:
                            const EdgeInsets.only(bottom: Space.x2),
                        leading: Icon(
                          Icons.folder_open_rounded,
                          size: 18,
                          color: p.inkSecondary,
                        ),
                        title: Text(
                          'Технические сведения',
                          style: AppTypography.label.copyWith(color: p.ink),
                        ),
                        initiallyExpanded: false,
                        children: [
                          _StorageLocationBlock(palette: p),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _HomeDraftChoice { stay, discard, save }

Future<bool> _confirmReplaceDirtyDraft(
  BuildContext context,
  WidgetRef ref,
) async {
  final p = Palette.of(context);
  final notifier = ref.read(dishProvider.notifier);
  final canSave = ref.read(dishProvider).ingredients.isNotEmpty;
  final choice = await showDialog<_HomeDraftChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        canSave ? 'Сохранить текущее блюдо?' : 'Заменить открытый черновик?',
      ),
      content: Text(
        canSave
            ? 'В открытом блюде есть несохранённые правки. '
                'Сохранить их в «Мои блюда» перед переходом?'
            : 'В открытом черновике есть несохранённые правки. '
                'Если продолжить без сохранения, они пропадут.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, _HomeDraftChoice.stay),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _HomeDraftChoice.discard),
          style: TextButton.styleFrom(foregroundColor: p.danger),
          child: const Text('Не сохранять'),
        ),
        if (canSave)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _HomeDraftChoice.save),
            child: const Text('Сохранить и продолжить'),
          ),
      ],
    ),
  );
  if (choice == null || choice == _HomeDraftChoice.stay) {
    return false;
  }
  if (choice == _HomeDraftChoice.discard) {
    notifier.discardChanges();
    return true;
  }
  try {
    await notifier.saveCurrentToLibrary();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(e, prefix: 'Не удалось сохранить расчёт'),
          ),
        ),
      );
    }
    return false;
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
          color: p.accentSoft,
          borderRadius: Radii.cardAll,
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

/// Шторка восстановления сохранённых рецептов и своих продуктов из JSON-копии.
class _RestoreBackupSheet extends ConsumerStatefulWidget {
  const _RestoreBackupSheet();

  @override
  ConsumerState<_RestoreBackupSheet> createState() =>
      _RestoreBackupSheetState();
}

class _RestoreBackupSheetState extends ConsumerState<_RestoreBackupSheet> {
  final TextEditingController _jsonCtrl = TextEditingController();
  ParsedBackup? _parsed;
  String? _parseError;
  bool _busy = false;

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _onRawChanged(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _parsed = null;
        _parseError = null;
      });
      return;
    }
    try {
      final parsed = BackupService.parseBackup(trimmed);
      setState(() {
        _parsed = parsed;
        _parseError = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _parsed = null;
        _parseError = e.message;
      });
    } catch (_) {
      setState(() {
        _parsed = null;
        _parseError = 'Не удалось разобрать JSON резервной копии';
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      setState(() {
        _parseError = 'Буфер обмена пуст';
      });
      return;
    }
    _jsonCtrl.text = text;
    _onRawChanged(text);
  }

  Future<void> _applyRestore({required bool replaceExisting}) async {
    final parsed = _parsed;
    if (parsed == null || _busy) return;
    if (replaceExisting) {
      final p = Palette.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Заменить библиотеку?'),
          content: const Text(
            'Текущие сохранённые блюда и свои продукты будут заменены '
            'данными из резервной копии.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: p.danger),
              child: const Text('Заменить'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final dishesAdded =
          await ref.read(savedDishesProvider.notifier).importDishes(
                parsed.savedDishes,
                replaceExisting: replaceExisting,
              );
      final productsAdded =
          await ref.read(customProductsProvider.notifier).importProducts(
                parsed.customProducts,
                replaceExisting: replaceExisting,
              );
      final favoritesAdded = parsed.favoriteProducts.isNotEmpty
          ? await ref.read(favoriteProductsProvider.notifier).importFavorites(
                parsed.favoriteProducts,
                replaceExisting: replaceExisting,
              )
          : 0;
      AppHaptics.commit();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context);
      final favPart =
          favoritesAdded > 0 ? ', избранных ${replaceExisting ? favoritesAdded : '+$favoritesAdded'}' : '';
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              replaceExisting
                  ? 'Библиотека заменена: блюд $dishesAdded, своих продуктов $productsAdded$favPart'
                  : 'Добавлено: блюд +$dishesAdded, своих продуктов +$productsAdded$favPart',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _parseError = friendlyErrorMessage(
          e,
          prefix: 'Не удалось восстановить данные',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final parsed = _parsed;
    final hasItems = parsed != null &&
        (parsed.savedDishes.isNotEmpty ||
            parsed.customProducts.isNotEmpty ||
            parsed.favoriteProducts.isNotEmpty);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.x4,
        0,
        Space.x4,
        Space.x4 + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Восстановление из копии',
            style: AppTypography.title.copyWith(color: p.ink),
          ),
          const SizedBox(height: Space.x1),
          Text(
            'Вставьте JSON из файла резервной копии или буфера обмена.',
            style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
          ),
          const SizedBox(height: Space.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('backup-paste-btn'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: _busy ? null : _pasteFromClipboard,
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Вставить из буфера'),
            ),
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const ValueKey('backup-json-field'),
            controller: _jsonCtrl,
            minLines: 4,
            maxLines: 7,
            onChanged: _onRawChanged,
            style: AppTypography.numSm.copyWith(color: p.ink),
            decoration: InputDecoration(
              labelText: 'JSON резервной копии',
              hintText: '{"format": "povarspravka-backup", ...}',
              errorText: _parseError,
            ),
          ),
          if (parsed != null) ...[
            const SizedBox(height: Space.x3),
            DecoratedBox(
              key: const ValueKey('backup-preview-card'),
              decoration: BoxDecoration(
                color: p.sunken,
                borderRadius: Radii.cardAll,
                border: Border.all(color: p.border),
              ),
              child: Padding(
                padding: Space.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasItems
                          ? 'Готово к восстановлению'
                          : 'Копия не содержит блюд и продуктов',
                      style: AppTypography.label.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: Space.x1),
                    Text(
                      parsed.favoriteProducts.isNotEmpty
                          ? 'Блюд: ${parsed.savedDishes.length} · '
                              'Своих продуктов: ${parsed.customProducts.length} · '
                              'Избранных: ${parsed.favoriteProducts.length}'
                          : 'Блюд: ${parsed.savedDishes.length} · '
                              'Своих продуктов: ${parsed.customProducts.length}',
                      style:
                          AppTypography.bodySm.copyWith(color: p.inkSecondary),
                    ),
                    if (parsed.exportedAt != null) ...[
                      const SizedBox(height: Space.x1),
                      Text(
                        'Создана: ${parsed.exportedAt!.toLocal().toString().substring(0, 16)}',
                        style:
                            AppTypography.caption.copyWith(color: p.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.x4),
          FilledButton(
            key: const ValueKey('backup-merge-btn'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
            ),
            onPressed: (!hasItems || _busy)
                ? null
                : () => _applyRestore(replaceExisting: false),
            child: const Text('Добавить к текущим'),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton(
            key: const ValueKey('backup-replace-btn'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
              foregroundColor: p.danger,
            ),
            onPressed: (!hasItems || _busy)
                ? null
                : () => _applyRestore(replaceExisting: true),
            child: const Text('Заменить библиотеку'),
          ),
        ],
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
    return Padding(
      key: const ValueKey('storage-location-block'),
      padding: const EdgeInsets.only(top: Space.x1),
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

class _InfoSection extends StatelessWidget {
  final Palette palette;
  final IconData icon;
  final String title;
  final String body;

  const _InfoSection({
    required this.palette,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: p.inkSecondary),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                title,
                style: AppTypography.label.copyWith(color: p.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x1),
        Text(
          body,
          style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
        ),
      ],
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
    final hasIngredients = dish.ingredients.isNotEmpty;
    final hasTitle = dish.title.trim().isNotEmpty;
    final hasDraft = hasIngredients || hasTitle;
    // STATE-01: карточка черновика не имеет права ронять домашний экран —
    // невычислимое блюдо показывает прочерки.
    final calc = CalculationEngine.tryCalculate(dish);
    final title = !hasTitle
        ? (hasIngredients ? 'Черновик без названия' : 'Новый расчёт')
        : dish.title.trim();

    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final stackHeader = AppLayout.shouldStackActions(width, textScale);

    return TactilePress(
      child: GroupedSurface(
        onTap: hasDraft ? onOpen : onNew,
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stackHeader) ...[
              Text(
                hasDraft ? 'Открытый расчёт' : 'Новый расчёт',
                style: AppTypography.caption.copyWith(
                  color: p.inkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.x1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      hasDraft ? 'Продолжить' : 'Открыть',
                      style: AppTypography.label.copyWith(color: p.accent),
                    ),
                  ),
                  const SizedBox(width: Space.x1),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: p.accent,
                  ),
                ],
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        hasDraft ? 'Открытый расчёт' : 'Новый расчёт',
                        style: AppTypography.caption.copyWith(
                          color: p.inkSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              hasDraft ? 'Продолжить' : 'Открыть',
                              style: AppTypography.label.copyWith(
                                color: p.accent,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Space.x1),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: p.accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.x2),
            Text(
              title,
              style: AppTypography.headline.copyWith(
                color: p.ink,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (hasIngredients) ...[
              const SizedBox(height: Space.x1),
              if (calc != null)
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      calc.hasYield
                          ? '${CalculationEngine.formatKcal(calc.per100gKcal)} ккал / 100 г'
                          : '${CalculationEngine.formatKcal(calc.cookedKcal)} ккал всего',
                      style: AppTypography.headline.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${pluralIngredients(dish.ingredients.length)} · '
                      '${calc.usesLossTable && !calc.hasYield ? 'вес готового блюда не указан' : 'выход ${CalculationEngine.formatGrams(calc.yieldGrams)} г'}',
                      style: AppTypography.numSm
                          .copyWith(color: p.inkSecondary),
                    ),
                  ],
                )
              else
                Text(
                  '${pluralIngredients(dish.ingredients.length)} · выход — г · — ккал',
                  style: AppTypography.numSm.copyWith(color: p.inkSecondary),
                ),
            ] else if (hasTitle) ...[
              const SizedBox(height: Space.x1),
              Text(
                'Ингредиенты ещё не добавлены',
                style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onSearchToggle;
  final bool searchActive;
  final Widget? sortControl;

  const _SectionHeader({
    required this.title,
    this.trailing,
    this.onSearchToggle,
    this.searchActive = false,
    this.sortControl,
  });

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
        if (sortControl != null) ...[
          const SizedBox(width: Space.x1),
          sortControl!,
        ],
        if (onSearchToggle != null) ...[
          const SizedBox(width: Space.x1),
          IconButton(
            key: const ValueKey('home-library-search-toggle'),
            tooltip: 'Поиск по моим блюдам',
            onPressed: onSearchToggle,
            icon: Icon(
              searchActive ? Icons.search_off_rounded : Icons.search_rounded,
              size: 20,
              color: searchActive ? p.accent : p.inkSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final Palette palette;

  const _EmptyLibrary({required this.palette});

  @override
  Widget build(BuildContext context) {
    return GroupedSurface(
      padding: const EdgeInsets.all(Space.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: Radii.fieldAll,
            ),
            child: const Center(child: AppScaleGlyph(size: 20)),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Здесь будут ваши блюда',
                  style: AppTypography.label.copyWith(color: palette.ink),
                ),
                const SizedBox(height: Space.x1),
                Text(
                  'Сохранённые рецепты появятся на этом экране — к ним можно вернуться в любой момент.',
                  style:
                      AppTypography.bodySm.copyWith(color: palette.inkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка сохранённого блюда: сгруппированная строка `R = 20 dp`.
class _SavedDishCard extends ConsumerWidget {
  final Dish dish;
  final bool isFirst;
  final bool isLast;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onStartSelect;

  const _SavedDishCard({
    required this.dish,
    this.isFirst = true,
    this.isLast = true,
    this.isSelecting = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onStartSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    // STATE-01: карточка сохранённого блюда тоже не имеет права ронять экран.
    final calc = CalculationEngine.tryCalculate(dish);
    final title =
        dish.title.trim().isEmpty ? 'Блюдо без названия' : dish.title.trim();
    final categoryLabel = DishCategories.labelOf(dish.category);

    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final showRightKcal = calc != null &&
        !AppLayout.isNarrow(media.width) &&
        !AppLayout.isLargeText(textScale);

    final rowRadius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? Radii.card : 0),
      bottom: Radius.circular(isLast ? Radii.card : 0),
    );
    final prefixParts = <String>[
      if (categoryLabel != null) categoryLabel,
      pluralIngredients(dish.ingredients.length),
    ].join(' · ');

    return Semantics(
      selected: isSelected,
      checked: isSelecting ? isSelected : null,
      child: TactilePress(
        child: Container(
          margin: EdgeInsets.only(bottom: isLast ? Space.x2 : 0),
          decoration: BoxDecoration(
            color: isSelected ? p.accentSoft : p.surface,
            borderRadius: rowRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onLongPress: isSelecting ? onToggleSelect : onStartSelect,
              onTap: () async {
                if (isSelecting) {
                  onToggleSelect?.call();
                  return;
                }
                final notifier = ref.read(dishProvider.notifier);
                if (notifier.isDirty) {
                  final ok = await _confirmReplaceDirtyDraft(context, ref);
                  if (!ok || !context.mounted) return;
                }
                notifier.loadDish(dish);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.x4,
                      Space.x3,
                      Space.x2,
                      Space.x3,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: AppTypography.headline
                                          .copyWith(color: p.ink),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (showRightKcal) ...[
                                    const SizedBox(width: Space.x2),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          CalculationEngine.formatKcal(
                                            calc.hasYield
                                                ? calc.per100gKcal
                                                : calc.cookedKcal,
                                          ),
                                          style:
                                              AppTypography.headline.copyWith(
                                            color: p.ink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          calc.hasYield
                                              ? 'ккал / 100 г'
                                              : 'ккал всего',
                                          style: AppTypography.caption.copyWith(
                                            color: p.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: Space.x1),
                              Text(
                                calc == null
                                    ? '$prefixParts · выход — г · — ккал'
                                    : showRightKcal
                                        ? '$prefixParts · '
                                            '${calc.usesLossTable && !calc.hasYield ? 'вес не указан' : '${CalculationEngine.formatGrams(calc.yieldGrams)} г'} · '
                                            'Б ${CalculationEngine.formatMacro(calc.hasYield ? calc.per100gProtein : calc.cookedProtein)} · '
                                            'Ж ${CalculationEngine.formatMacro(calc.hasYield ? calc.per100gFat : calc.cookedFat)} · '
                                            'У ${CalculationEngine.formatMacro(calc.hasYield ? calc.per100gCarbs : calc.cookedCarbs)}'
                                        : '$prefixParts · '
                                            '${calc.usesLossTable && !calc.hasYield ? 'вес не указан' : '${CalculationEngine.formatGrams(calc.yieldGrams)} г'} · '
                                            '${CalculationEngine.formatKcal(calc.hasYield ? calc.per100gKcal : calc.cookedKcal)} '
                                            '${calc.hasYield ? 'ккал / 100 г' : 'ккал всего'} · '
                                            'Б ${CalculationEngine.formatMacro(calc.hasYield ? calc.per100gProtein : calc.cookedProtein)} · '
                                            'Ж ${CalculationEngine.formatMacro(calc.hasYield ? calc.per100gFat : calc.cookedFat)} · '
                                            'У ${CalculationEngine.formatMacro(calc.hasYield ? calc.per100gCarbs : calc.cookedCarbs)}',
                                style: AppTypography.numSm
                                    .copyWith(color: p.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.x1),
                        SizedBox(
                          width: kMinTapTarget,
                          height: kMinTapTarget,
                          child: isSelecting
                              ? Center(
                                  child: Container(
                                    width: Space.x6,
                                    height: Space.x6,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? p.accent
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            isSelected ? p.accent : p.border,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check_rounded,
                                            size: 16,
                                            color: p.onAccent,
                                          )
                                        : null,
                                  ),
                                )
                              : PopupMenuButton<String>(
                              tooltip: 'Действия с блюдом',
                              icon: Icon(Icons.more_vert_rounded,
                                  color: p.inkMuted),
                              onSelected: (value) async {
                                final notifier =
                                    ref.read(savedDishesProvider.notifier);
                                if (value == 'select') {
                                  onStartSelect?.call();
                                  return;
                                }
                                if (value == 'share') {
                                  await ShareRecipeSheet.show(
                                    context,
                                    dish: dish,
                                    customProducts:
                                        ref.read(customProductsProvider),
                                  );
                                  return;
                                }
                                if (value == 'category') {
                                  final chosen =
                                      await _pickDishCategory(context, dish);
                                  if (chosen == null || !context.mounted) {
                                    return;
                                  }
                                  final nextCat =
                                      chosen.isEmpty ? null : chosen;
                                  try {
                                    await notifier.setDishCategory(
                                        dish.id, nextCat);
                                    if (ref.read(dishProvider).id == dish.id) {
                                      ref
                                          .read(dishProvider.notifier)
                                          .setCategory(nextCat);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            friendlyErrorMessage(
                                              e,
                                              prefix:
                                                  'Не удалось обновить категорию',
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                  return;
                                }
                                if (value == 'delete') {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Удалить блюдо?'),
                                      content: Text(
                                        'Блюдо «$title» будет удалено из «Моих блюд».',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Отмена'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          style: TextButton.styleFrom(
                                            foregroundColor: p.danger,
                                          ),
                                          child: const Text('Удалить'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !context.mounted) {
                                    return;
                                  }
                                }
                                try {
                                  if (value == 'copy') {
                                    await notifier.duplicateDish(dish);
                                  }
                                  if (value == 'delete') {
                                    await notifier.deleteDish(dish.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text('Удалено: $title'),
                                          action: SnackBarAction(
                                            label: 'Отменить',
                                            onPressed: () {
                                              notifier
                                                  .saveDish(dish)
                                                  .then<void>((_) {},
                                                      onError: (Object _) {});
                                            },
                                          ),
                                        ),
                                      );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          friendlyErrorMessage(
                                            e,
                                            prefix:
                                                'Не удалось выполнить действие',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'select',
                                  child: Text('Выбрать для меню / экспорта'),
                                ),
                                PopupMenuItem(
                                  value: 'share',
                                  child: Text('Поделиться рецептом'),
                                ),
                                PopupMenuItem(
                                  value: 'category',
                                  child: Text('Категория'),
                                ),
                                PopupMenuItem(
                                  value: 'copy',
                                  child: Text('Дублировать'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить'),
                                ),
                              ],
                            ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Container(
                      height: 1,
                      margin: const EdgeInsets.only(left: Space.x4),
                      color: isSelected
                          ? p.accent.withOpacity(0.18)
                          : p.divider,
                    ),
                  ],
                ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Быстрый выбор категории блюда из меню карточки на главном экране.
/// Возвращает `''` для «Без категории», id категории или `null` при отмене.
Future<String?> _pickDishCategory(BuildContext context, Dish dish) {
  final p = Palette.of(context);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => AppSheetScaffold(
      title: 'Категория блюда',
      showHandle: true,
      maxHeightFactor: 0.75,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Без категории'),
            trailing: dish.category == null
                ? Icon(Icons.check_rounded, color: p.accent)
                : null,
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final item in DishCategories.all)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.label),
              trailing: dish.category == item.id
                  ? Icon(Icons.check_rounded, color: p.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, item.id),
            ),
        ],
      ),
    ),
  );
}

/// Нижний док главного экрана в режиме выбора блюд: Сравнить, Меню, Экспорт.
class _SelectionDock extends StatelessWidget {
  final int selectedCount;
  final VoidCallback? onCompare;
  final VoidCallback? onMenu;
  final VoidCallback? onExport;

  const _SelectionDock({
    required this.selectedCount,
    required this.onCompare,
    required this.onMenu,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackActions = AppLayout.shouldStackActions(width, textScale);
    final compactDock = stackActions && size.height < 640;

    final String hint = switch (selectedCount) {
      0 => 'Выберите блюда из списка',
      1 => 'Выберите ещё 1 блюдо для сравнения или соберите меню',
      2 => 'Можно сравнить 2 блюда, собрать меню или выгрузить',
      _ => 'Соберите меню или выгрузите сборник бланков',
    };

    Widget buildAction({
      required Key buttonKey,
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
      bool primary = false,
      bool horizontal = false,
    }) {
      final enabled = onTap != null;
      final bg = !enabled
          ? p.sunken.withOpacity(0.55)
          : (primary ? p.accent : p.sunken);
      final fg = !enabled
          ? p.inkMuted
          : (primary ? p.onAccent : p.ink);

      return TactilePress(
        enabled: enabled,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: Material(
            key: buttonKey,
            color: bg,
            borderRadius: Radii.fieldAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTapTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.x2,
                    vertical: Space.x2,
                  ),
                  child: horizontal
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: fg),
                            const SizedBox(width: Space.x2),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: AppTypography.label.copyWith(color: fg),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: fg),
                            const SizedBox(height: Space.x1),
                            Text(
                              label,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: AppTypography.caption.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final Widget actionsBlock = stackActions
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildAction(
                buttonKey: const ValueKey('selection-compare-btn'),
                icon: Icons.compare_arrows_rounded,
                label: 'Сравнить',
                onTap: onCompare,
                horizontal: true,
              ),
              const SizedBox(height: Space.x1),
              buildAction(
                buttonKey: const ValueKey('selection-menu-btn'),
                icon: Icons.restaurant_rounded,
                label: 'Меню',
                onTap: onMenu,
                horizontal: true,
              ),
              const SizedBox(height: Space.x1),
              buildAction(
                buttonKey: const ValueKey('selection-export-btn'),
                icon: Icons.ios_share_rounded,
                label: 'Экспорт',
                onTap: onExport,
                primary: true,
                horizontal: true,
              ),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: buildAction(
                  buttonKey: const ValueKey('selection-compare-btn'),
                  icon: Icons.compare_arrows_rounded,
                  label: 'Сравнить',
                  onTap: onCompare,
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: buildAction(
                  buttonKey: const ValueKey('selection-menu-btn'),
                  icon: Icons.restaurant_rounded,
                  label: 'Меню',
                  onTap: onMenu,
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: buildAction(
                  buttonKey: const ValueKey('selection-export-btn'),
                  icon: Icons.ios_share_rounded,
                  label: 'Экспорт',
                  onTap: onExport,
                  primary: true,
                ),
              ),
            ],
          );

    return AppBottomBar(
      floating: !compactDock,
      padding: compactDock
          ? EdgeInsets.symmetric(
              horizontal: Space.gutter(width),
              vertical: Space.x1,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x2,
              Space.x1,
              Space.x2,
              Space.x2,
            ),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: p.inkSecondary),
            ),
          ),
          actionsBlock,
        ],
      ),
    );
  }
}

/// Нижний док главного экрана: парящая капсула с главным действием и базой.
class _HomeDock extends StatelessWidget {
  final VoidCallback onNewCalculation;
  final VoidCallback onCatalog;

  const _HomeDock({
    required this.onNewCalculation,
    required this.onCatalog,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackVertically = AppLayout.shouldStackActions(width, textScale);
    final compactDock = stackVertically && size.height < 640;
    final narrowRow = !stackVertically && AppLayout.isNarrow(width);
    final btnPadding = narrowRow
        ? const EdgeInsets.symmetric(
            horizontal: Space.x3,
            vertical: Space.x2,
          )
        : null;

    Widget buildBtnChild(IconData icon, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: Space.x2),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    final newBtn = FilledButton(
      onPressed: onNewCalculation,
      style: FilledButton.styleFrom(padding: btnPadding),
      child: buildBtnChild(Icons.add_rounded, 'Новый расчёт'),
    );
    final catalogBtn = OutlinedButton(
      onPressed: onCatalog,
      style: OutlinedButton.styleFrom(padding: btnPadding),
      child: buildBtnChild(Icons.search_rounded, 'Справочник'),
    );

    return AppBottomBar(
      floating: !compactDock,
      padding: compactDock
          ? EdgeInsets.symmetric(
              horizontal: Space.gutter(width),
              vertical: Space.x1,
            )
          : null,
      child: stackVertically
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                newBtn,
                SizedBox(height: compactDock ? Space.x1 : Space.x2),
                catalogBtn,
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: newBtn),
                  const SizedBox(width: Space.x2),
                  Expanded(child: catalogBtn),
                ],
              ),
            ),
    );
  }
}
