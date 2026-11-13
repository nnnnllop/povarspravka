# ВСЕОБЪЕМЛЮЩИЙ АУДИТ БИЗНЕС-ЛОГИКИ И МАТЕМАТИЧЕСКОГО ДВИЖКА
## «Поварская справка» · `C:\projects\povarspravka\app`

| | |
|---|---|
| **Дата** | 2026-10-30 |
| **Объект** | `app/lib/**` — расчётное ядро, хранилище, провайдеры состояния, конвертер мер |
| **НЕ объект** | UI-компоновка и дизайн (отдельный этап). `app/assets/db/reference.db` — **не изменялась** (mtime 19:12, до начала аудита; открывалась только `mode=ro`) |
| **Метод** | 5 специализированных субагентов + сводные кросс-проверки главного аудитора |
| **Инструмент** | Flutter 3.24.5 / Dart 3.5.4 (`audit_artifacts/flutter-sdk`) |
| **Улика** | 457 новых исполняемых Dart-тестов (433 ✅ / 24 🔴) в `app/test/audit_*_test.dart` |

---

# 1. EXECUTIVE SUMMARY

## 1.1. Вердикт

> # 🔴 ТРЕБУЕТСЯ УСТРАНЕНИЕ БЛОКЕРОВ
>
> К переходу на этап UI **переходить нельзя**. Найдено 5 дефектов уровня P0, из которых
> три — потери данных пользователя и один — невычислимость физически корректных блюд,
> валящая экран в красную страницу ошибки.

## 1.2. Интегральный рейтинг надёжности бизнес-логики

# **4.1 / 10**

| Домен | Вес | Оценка | Обоснование |
|---|---:|---:|---|
| Численная арифметика (`CalculationMath`, BigInt HALF-UP) | 20 % | **9.5** | 11,7 млн точек сетки `energy()` — 0 расхождений; 30 000 round-trip — 0 дрейфа; детерминизм 1000/1000 |
| Формула Брутто↔Нетто | 10 % | **9.0** | Точна; дефект только на квантовании 0,1 г на границе UI при отходах > 90 % |
| Пищевая ценность, Retenion Factors | 15 % | **3.0** | Одна глобальная тройка 0.94/0.88/0.91 на *любое* блюдо; у холодных блюд занижает до −12 %, у бульона завышает жир в 10,8× |
| Модель выхода готового блюда | 15 % | **2.5** | Гидратации/уварки нет вообще: «Итого (сырьё)» = слепое суммирование, вода = 60 % массы каши |
| Конвертер мер и ввод | 10 % | **6.0** | Запятая/точка работают, дробь работает; но лимит 7 символов молча съедает ввод, ручной % отходов теряется |
| Слой хранения (I/O) | 15 % | **7.0** | CRC + .bak + атомарный rename — добротно; но CRC обходится через «legacy», кросс-инстансная гонка теряет библиотеку |
| Состояние и реактивность | 10 % | **5.0** | Дебаунс поиска, isDirty, очередь записи — верны; но провайдер расчёта бросает в UI, «Новый расчёт» стирает черновик без вопроса |
| Экспорт (DOCX/XLSX/PDF) | 5 % | **7.0** | Форматтеры используют те же `formatGrams/Macro/Kcal`; масштаб проверен |

## 1.3. Статистика

| Показатель | Значение |
|---|---:|
| Проверено формул и правил расчёта | **42** |
| Написано новых исполняемых тестов (файлов `audit_*_test.dart`: 31) | **457** |
| Из них «красных» (воспроизводят дефект прямо сейчас) | **24** |
| Тестов-стражей (зелёные, фиксируют хорошее поведение) | **433** |
| Обнаружено проблем — **всего** | **38** |
| — 🔴 **BLOCKER (P0)** | **5** |
| — 🟠 **CRITICAL (P1)** | **7** |
| — 🟡 **MAJOR (P2)** | **11** |
| — 🔵 **MINOR (P3)** | **10** |
| — ⚪ **NITPICK (P4)** | **5** |
| Закрыто как опровергнутая гипотеза (доказано тестом) | **4** |

## 1.4. Что действительно сделано хорошо (чтобы не сгущать краски)

Это не «код выглядит чисто» — это проверено запуском:

- **`CalculationMath` — лучшая часть проекта.** Арифметика в `BigInt` с HALF-UP по
  десятичному представлению double. `0.1 + 0.2` не всплывает нигде. `sumRounded(1000 × 0.1) == 100.0`
  бит-в-бит. Визуального float-мусора `49.999999999999994` в приложении **нет**.
- **Печатные строки БЖУ сходятся с печатным итогом до копейки** (10.01 не появляется из 10.00):
  инвариант «итог = сумма напечатанных строк» держится — это проверено на 4000 блюдах.
- **Деление на ноль полностью закрыто.** Пустой рецепт даёт `0.0` на 100 г, а не `NaN`.
  `portion()` на пустом блюде бросает контролируемый `StateError`. 33 варианта мусорного
  ввода (`NaN`, `Infinity`, `1e999`, `٠١٢`, RTL, lone surrogate) дают `ArgumentError`, а не `FormatException`.
- **Слой хранения сделан честно:** `.tmp` + `flush: true` + `.bak` + атомарный `rename`; 50 циклов сохранения
  не оставляют ни одного «сиротского» файла; ни один читатель не увидел пустой файл; Unicode
  (ZWSP, ZWJ-эмодзи, NUL, lone surrogate, 5000 символов) переживает round-trip байт-в-байт.
- **Рецепт автономен от БД:** подменённый до взрыва `ProductRepository` не вызывается ни разу при расчёте.

---

# 2. КЛАССИФИКАЦИЯ ДЕФЕКТОВ (SEVERITY MATRIX)

## 2.1. 🔴 BLOCKER (P0) — 5

| ID | Дефект | Влияние |
|---|---|---|
| **LOGIC-01** | Гард «масса БЖУ ≤ выход» бросает `ArgumentError` на физически корректных жирных блюдах | Блюдо невозможно рассчитать/сохранить/напечатать |
| **STATE-01** | Тот же `ArgumentError` вылетает из `calculationResultProvider` → **Red Screen** на 3 экранах | Открытие рецепта = пустой экран |
| **STATE-13** | «Новый расчёт» стирает несохранённый черновик **без вопроса** | Мгновенная потеря рецепта |
| **STATE-06b** | Правка до завершения загрузки → восстановление черновика отменяется → автозапись пустого черновика затирает его | Потеря рецепта при холодном старте |
| **GOST-01** | Вода/бульон входит в «Итого (сырьё)»: выход = слепая сумма; гидратации и уварки нет | ккал/100 г пюре занижена на **−31,5 %**, котлет — на **−24,3 %** |

## 2.2. 🟠 CRITICAL (P1) — 7

| ID | Дефект |
|---|---|
| **STATE-11 / MATH-09** | Ручной % отходов, введённый в шите, **не доезжает** до рецепта (`onProductUpdated: (updated) {}`) |
| **GOST-02** | Сохранность — одна глобальная тройка 0.94/0.88/0.91 для *любого* блюда: холодный салат занижен на **−10,7 %**, бульон завышен на **+184 %** |
| **STATE-04b** | Неудачная запись черновика глушится: `isDirty=false`, на диске пусто |
| **IO-05** | Два экземпляра хранилища на одном каталоге → библиотека форкается, ветка теряется |
| **MATH-05** | `customYield = 0,1 г` проходит валидацию → десятки миллионов ккал/100 г |
| **FUZZ-13** | Автосейв черновика переписывает всю библиотеку: **723–1613 мс** на 200 блюд, растёт линейно |
| **GOST-03** | Бульон/отвар: нормы «потери при варке» подменены `retention`, физически неверная модель экстракции |

## 2.3. 🟡 MAJOR (P2) — 11

| ID | Дефект |
|---|---|
| **FUZZ-11 / STATE-08** | Нумпад: лимит 7 символов молча режет ввод; `12345,67` → `12345,6`; нет подсказки |
| **MATH-02** | «Округление-затем-сумма» для ккал: итог расходится с колонкой на **1,0–1,6 ккал** |
| **MATH-03** | `waste = 100 %` молча превращает продукт в 0 г |
| **MATH-04** | Round-trip через *печатное* нетто (0,1 г) при отходах 99,8 % даёт дрейф **24 г брутто** |
| **MATH-08** | `retention = 0` допустим → правдоподобное «0,0 ккал» для килограмма стейка |
| **FUZZ-01** | `kcal = NaN / ±Infinity / отрицательный` проходит валидацию; сохранение падает с сырым `JsonUnsupportedObjectError` |
| **IO-01 (DW-01)** | Отходы заполнены у **141 из 1108** продуктов Скурихина (12,7 %); тип 0% молча означает «потерь нет» |
| **IO-02** | Документ без `crc32` принимается как «legacy» → CRC обходится |
| **IO-03** | Откат на устаревший `.bak` без уведомления; read-only main блокирует восстановление навсегда |
| **STATE-06a** | Правка до загрузки не поднимает `isDirty` → закрытие без вопроса |
| **STATE-10b** | `restoreIngredient` не привязан к блюду → восстановление вставляет ингредиент в *другое* блюдо |
| **STATE-04c** | `saveCurrentToLibrary()` тоже глушит ошибку записи |

## 2.4. 🔵 MINOR (P3) — 10

`MATH-06` (`formatGrams(1.5e21)` → `9223372036854775807`), `MATH-07` (`1e-7` печатается как «0»),
`FUZZ-02` (`round1(maxFinite)` → Infinity, недостижимо из UI), `FUZZ-04` (отрицательный kcal),
`FUZZ-05` (0,05 г → 0,1 г, специи), `FUZZ-06` (1000 строк × 0,01 г → «Итого 0 г»),
`FUZZ-07` («1 000» отвергается), `FUZZ-08` (`parseInputDouble("-3")` = −3,0), `FUZZ-09` (`reorder` вне
диапазона → `RangeError`), `FUZZ-10` (`setCustomYield` молча игнорирует мусор), `STATE-07` (контроллеры
в двух диалогах не освобождаются), `STATE-12` («120,0» вместо «120» в мере), `STATE-10a` (нет Undo/Redo),
`IO-04` (первый save не создаёт `.bak`), `IO-06` (тихий in-memory fallback), `IO-07` (потеря незнакомых ключей),
`MATH-12` (карточки мастеров: двойное списание отходов), `MATH-13` (`retentionFat: 0.95` при жарке).

## 2.5. ⚪ NITPICK (P4) — 5

`masters_recipes.dart` смешивает массовые и нутриентные потери в комментариях; `expectedYieldGrams`
декларативен; `kcal` справочника не участвует в расчёте и не подписан; `blankKcalInDish` вызывается
в UI-тексте; `retention` назван «сохранностью», но хранит долю.

## 2.6. ✅ Опровергнутые гипотезы (это тоже результат аудита)

| Гипотеза из ТЗ | Проверено | Итог |
|---|---|---|
| «Exponent-notation ломает `CalculationMath.decimal`» | `decimal(1e-7)`, `decimal(1.5e21)`, `decimal(1e-300)`, `decimal(4.9e-324)` | **Опровергнуто** — парсинг верен на всём диапазоне |
| «`BigInt.parse("NaN")` → `FormatException` (необработанная)» | `decimal(NaN/±Inf)` | **Опровергнуто** — есть guard `if (!value.isFinite) throw`, это `ArgumentError` |
| «Бинарный дрейф в `wasteAdjusted(...,12)` / `grossFromNet`» | 10 000 комбинаций сетки + 20 000 случайных | **Опровергнуто** — 0 дрейфа; дрейф только от квантования 0,1 г в UI |
| «Двойной тап “Добавить” теряет ингредиент» | 50 быстрых `addIngredient` | **Опровергнуто** — все 50 на диске, id уникальны |
| «Гонка draft/state в `updateDraftReference` теряет правку» | 3 сценария чередования очередей | **Опровергнуто** — `saveAll` сериализует payload синхронно |
| «Unicode/эмодзи ломает хранилище» | 19 наборов (ZWSP, ZWJ, NUL, lone surrogate, 5000 символов) | **Опровергнуто** — байт-в-байт |

---

# 3. ДЕТАЛЬНЫЕ КАРТОЧКИ ДЕФЕКТОВ

---

## 🔴 LOGIC-01 — Гард «масса БЖУ ≤ выход» отвергает физически корректные блюда

**Локализация.** [calculation_engine.dart:50-55](app/lib/core/calculation/calculation_engine.dart#L50-L55),
`CalculationEngine.calculate`.

**Математическая сущность.**

Код проверяет:
$$\sum(\text{cookedProtein} + \text{cookedFat} + \text{cookedCarbs}) \le m_{вых} \quad \text{иначе } \texttt{throw ArgumentError}$$

Это ошибочная посылка. Масса БЖУ — **компонент** массы готового блюда, а не её верхняя
граница. Готовое блюдо = сухие вещества + вода + минералы; для эмульсий и жировых соусов
доля жира доходит до 85–99 г на 100 г. При `retentionFat = 0.88` масло 82,5 % жира даёт
72,6 г жира на 100 г, то есть **выход обязан быть ≥ 72,6 г**. Если повар указывает выход
соуса 60 г (часть жира впиталась в гарнир / ушла с пеной), приложение **отказывается считать**.

**Воспроизведение** — [`audit_lead_cross_checks_test.dart` › `LEAD-01`](app/test/audit_lead_cross_checks_test.dart):

```dart
final butter = Product(protein: 0.8, fat: 72.5, carbs: 1.3, kcal: 661, wastePct: 0,
                       name: 'Масло сливочное «Крестьянское»');
CalculationEngine.calculate(Dish(ingredients: [Ingredient(product: butter, weightGrams: 100)],
                                 customYieldGrams: 60));
```

Наблюдаемо:
```
ArgumentError: Cooked macronutrients mass (65.73 g) cannot exceed dish yield (60.0 g)
```
Подтверждено также: `MATH-B3.1` (масло 82,5 %, выход 60 г → `73.8 g` > `60.0 g`),
`LEAD-04` (говядина 2400 г, выход 750 г → `757.54 g` > `750.0 g` — рост сырья сам по себе
делает блюдо невычислимым).

**Риск для повара/производства.** Голландез, бер-блан, соус на вытопленном жире, «масло
для смазывания» — сохранить и распечатать технологическую карту **невозможно**. Если
`.bak` уже содержит такое блюдо, приложение не откроется (см. STATE-01).

**Рекомендуемый патч.**

```dart
-    final totalCookedMacros = CalculationMath.sumRounded(
-        [cookedProtein, cookedFat, cookedCarbs], 2);
-    if (CalculationMath.sumExceeds(
-        [cookedProtein, cookedFat, cookedCarbs], yieldGrams)) {
-      throw ArgumentError(
-        'Cooked macronutrients mass ($totalCookedMacros g) cannot exceed dish yield ($yieldGrams g)',
-      );
-    }
+    // Масса БЖУ — КОМПОНЕНТ массы блюда, а не её верхняя граница:
+    // жировой соус даёт до 85 г жира на 100 г выхода. Смысл теряет только
+    // неположительный выход (деление на 0 в строке «на 100 г»).
+    // Логическая несогласованность — не ошибка, а ПРЕДУПРЕЖДЕНИЕ в UI.
+    if (yieldGrams <= 0) {
+      throw ArgumentError('Dish yield must be positive (got $yieldGrams g)');
+    }
```
Обязательно в паре с **MATH-05**: поднять нижнюю границу `customYieldGrams` с `0.1` до `1.0`
в [calculation_validation.dart:46](app/lib/core/calculation/calculation_validation.dart#L46),
иначе снятие гарда откроет деление на 0,1 г.

---

## 🔴 STATE-01 — Невычислимое блюдо валит всё дерево виджетов в Red Screen

**Локализация.** [dish_provider.dart:31-34](app/lib/presentation/providers/dish_provider.dart#L31-L34):

```dart
final calculationResultProvider = Provider<CalculationResult>((ref) {
  final dish = ref.watch(dishProvider);
  return CalculationEngine.calculate(dish);   // бросает ArgumentError
});
```

Потребители без единого `try`: `RecipeEditorScreen.build` (строка 68), `HomeScreen` (`_ActiveDraftCard`
строка 271 и `_SavedDishCard` строка 395, считает **все** сохранённые блюда на каждый build),
`BlankPreviewScreen`. `main.dart` не содержит ни `ErrorWidget.builder`, ни `AsyncValue`.

**Математическая сущность.** `Provider` — синхронный; исключение пробрасывается в `build()`
и Flutter рендерит `ErrorWidget`. Это не «обработанная ошибка», это краш экрана.

**Воспроизведение** — [`audit_state_calc_crash_test.dart`](app/test/audit_state_calc_crash_test.dart):

```
STATE-01 engine message: Invalid argument(s): Cooked macronutrients mass (527.47 g)
                         cannot exceed dish yield (100.0 g)
STATE-01 editor: ErrorWidget count=1, header rendered=false
STATE-01 home:   ErrorWidget count=1, exceptions=[ArgumentError]
STATE-01 reachability: setCustomYield(100) is accepted by the provider (range-only check)
                       and immediately makes the provider throw.
```
Мой независимый тест [`LEAD-02`](app/test/audit_lead_cross_checks_test.dart) воспроизводит то же
через `ProviderContainer.read(calculationResultProvider)` → `ArgumentError`.

**Риск.** Повар вводит выход меньше суммы БЖУ (например, опечатался: `10` вместо `1000`) —
**весь экран становится красным**, кнопка «назад» остаётся единственным выходом. Хуже: если
невычислимое блюдо уже лежит в библиотеке, `HomeScreen` краснеет при каждом запуске — приложение
фактически недоступно, хотя остальные рецепты целы.

**Рекомендуемый патч.**

```dart
// dish_provider.dart
final calculationResultProvider = Provider<CalculationResult?>((ref) {
  final dish = ref.watch(dishProvider);
  try {
    return CalculationEngine.calculate(dish);
  } on ArgumentError catch (e) {
    ref.read(dishProvider.notifier).noteCalculationError(e.message.toString());
    return null;
  }
});
```
```dart
// home_screen.dart / recipe_editor_screen.dart
final calc = ref.watch(calculationResultProvider);
if (calc == null) return const CalcErrorBanner();   // «Проверьте выход блюда»
```
Плюс в `main.dart`: `ErrorWidget.builder = (d) => const FriendlyErrorPane();` как страховка.
Плюс `setCustomYield` должен сверять значение с `totalCookedMacros` и не принимать его молча.

---

## 🔴 STATE-13 — «Новый расчёт» стирает несохранённый черновик без подтверждения

**Локализация.** [home_screen.dart](app/lib/presentation/screens/home_screen.dart) —
обработчик `_newCalculation` → `createNewDish()`. В редакторе защита есть (`PopScope(canPop: !isDirty)`
+ `_confirmDiscardChanges`), на главном экране — **нет**.

**Воспроизведение** — [`audit_state_dialog_lifecycle_test.dart`](app/test/audit_state_dialog_lifecycle_test.dart),
кейс `"Новый расчёт" replaces 300 g…`:

```
observed: ingredients=0, title="", isDirty=true, dialogs=0
expected: диалог «Не сохранять изменения?»
```

**Риск.** Повар работал 20 минут, вернулся на главный, тапнул «Новый расчёт» — рецепт
исчез. `.bak` сохранит *предыдущее поколение*, но не текущую правку (автосохранение
сработало 300 мс назад) — то есть потеря реальная.

**Патч.** Тот же guard, что в редакторе:
```dart
Future<void> _newCalculation(BuildContext context, WidgetRef ref) async {
  final n = ref.read(dishProvider.notifier);
  if (n.isDirty) {
    final ok = await showDialog<bool>(...) ?? false;   // «Не сохранять?»
    if (!ok) return;
  }
  n.createNewDish();
  _openEditor(context);
}
```

---

## 🔴 STATE-06b — Правка до загрузки отменяет восстановление черновика → автозапись пустого черновика

**Локализация.** [dish_provider.dart:189-195](app/lib/presentation/providers/dish_provider.dart#L189-L195),
флаг `_editedBeforeLoad`.

**Сущность.** `_initFromStorage` асинхронна. Если пользователь успел что-то изменить до её
завершения, `_editedBeforeLoad` ставится в `true`, и черновик **с диска не восстанавливается**.
Первое же автосохранение записывает пустой черновик в **основной** файл; 300 г свёклы
остаются только в `.bak`, который при следующем успешном сохранении перезапишется.

**Воспроизведение** — [`audit_state_race_test.dart`](app/test/audit_state_race_test.dart),
кейс `"DEFECT: after an EARLY edit…"`:
```
observed: диск-черновик (300 г свёклы) не восстановлен; первая автозапись пишет пустой черновик
expected: черновик содержит 300 г свёклы (или правка отброшена с уведомлением)
```

**Патч.** Сравнивать контент, а не факт вызова; `_lastCleanSnapshot` ставить **до** выхода
из ветки ранней правки:
```dart
if (_editedBeforeLoad) {
  // Сохраняем правку, но и не теряем диск: слить по «непустому» правилу.
  final disk = data?.activeDraft;
  if (disk != null && disk.ingredients.isNotEmpty && state.ingredients.isEmpty) {
    // …либо предложить пользователю выбрать, либо восстановить и пометить dirty.
    _lastCleanSnapshot = _signature(state);   // правка остаётся «грязной»
  }
}
```

---

## 🔴 GOST-01 — Вода и бульон входят в «Итого (сырьё)»: выхода блюда по физике нет

**Локализация.** [calculation_engine.dart:16-17](app/lib/core/calculation/calculation_engine.dart#L16-L17)
(`rawTotalWeight` = Σ `netGramsRounded`), [dish.dart:35-43](app/lib/core/calculation/models/dish.dart#L35-L43)
(`effectiveYieldGrams` при `customYieldGrams == null` **равен этой же сумме**).

**Математическая сущность.**

Код:
$$m_{вых} = \sum_i m_{нетто,i} \qquad (\text{если повар не задал выход})$$

Правильно:
$$m_{вых} = \sum_i m_{нетто,i}\cdot K^{терм}_i \;+\; \text{вода добавленная, не испарившаяся}
\;\ne\; \sum_i \big(m_{нетто,i} + m_{воды,i}\big)$$

Вода — полноценный ингредиент в блюде (каша, борщ, тесто). В коде для неё **нет** ни
доли испарения, ни доли впитывания, ни коэффициента развариваемости. При этом Сборник
для гречки даёт приварку **+110 %** (100 г крупы → 210 г), для риса **+150 %**, для макаронных
изделий **+100 %** — ни одного из этих коэффициентов в модели нет.

**Воспроизведение** — [`audit_gost_yield_physics_test.dart`](app/test/audit_gost_yield_physics_test.dart):

```
A1: каша — Итого(сырьё)=250.0 г, выход=210.0 г, вода=150.0 г (60.0 % сырья)
A2: каша без custom yield — выход app=100.0 г vs норматив 210 г (−52.4 %)
A4: бульон — бульон без customYield: выход=336.0 г, норматив=300 г → +12.0 %
```

Полная ошибка по 10 блюдам при `customYieldGrams == null` (повар не знает выхода — самый
частый случай):

| Блюдо | Σ нетто | Норм. выход | Ошибка выхода | Ошибка ккал/100 г |
|---|---:|---:|---:|---:|
| Борщ сибирский | 1000 | 1000 | 0,00 % | 0,00 % |
| **Котлеты домашние** | 142,7 | 108 | **+32,13 %** | **−24,33 %** → 225,5 вместо 298,0 |
| **Каша гречневая** | 250 | 210 | **+19,05 %** | **−16,00 %** → 112,5 вместо 159,5 |
| **Пюре картофельное** | 365 | 250 | **+46,00 %** | **−31,50 %** → 93,5 вместо 136,5 |
| Оливье | 250 | 250 | 0,00 % | 0,00 % |
| Омлет паровой | 130 | 133,5 | −2,62 % | +2,70 % |
| **Бульон куриный** | 336 | 300 | **+12,00 %** | **−10,75 %** |
| Сырники | 140 | 140 | 0,00 % | 0,00 % |
| Бешамель | 1000 | 1000 | 0,00 % | 0,00 % |
| Морс клюквенный | 1000 | 1000 | 0,00 % | 0,00 % |

**Риск.** Это не «погрешность округления» — это **систематическое занижение калорийности
на четверть** для жареных блюд и на треть для пюре, причём **молча**. Технологическая
карта, заверенная поваром, будет содержать неверную энергетическую ценность в разы
превышающую допустимое (ГОСТ 31987 допускает ±5 % по расчёту).

**Рекомендуемый патч.** Ввести класс обработки и модель выхода:

```dart
enum HeatProcess { cold, boil, steam, fryMain, stew, bake }

class Dish {
  final HeatProcess process;
  /// Доля испарения добавленной воды. Для boil=0.35 … (по сборнику)
  final double addedWaterEvaporation;
}

double get effectiveYieldGrams {
  if (customYieldGrams != null) return CalculationMath.round1(customYieldGrams!);
  // Вода испаряется, крупа впитывает — вводить через коэффициент развариваемости
  // продукта (гречка 2.1, рис 2.5, макароны 2.0), а не суммировать «Вода».
  return CalculationMath.round1(
      ingredients.fold<double>(0, (s, i) => s + i.contributionToYield(process)));
}
```
Поле «Вода питьевая» (оно уже есть в `reference.db`, id из `supplement`) должно
участвовать в массе **только через** коэффициент поглощения, а не как ещё одно слагаемое.

---

## 🟠 STATE-11 / MATH-09 — Ручной процент отходов, введённый в шите, не доезжает до рецепта

**Локализация.**
[search_product_modal.dart:480](app/lib/presentation/screens/search_product_modal.dart#L480) —
`onProductUpdated: (updated) {}` (пустой колбэк);
[search_product_modal.dart:481-483](app/lib/presentation/screens/search_product_modal.dart#L481-L483) —
`_addToRecipe(product, …)` с **исходным** продуктом;
[custom_numpad.dart:333-341](app/lib/presentation/widgets/custom_numpad.dart#L333-L341) —
`effectiveProduct` с новым `wastePct` уходит **только** в `onProductUpdated`.

**Сущность.** Сезонные отходы картофеля (осень 20 %, зима 25 %, весна 40 %) — требование
ТЗ, и пресеты для них **есть** (`_getSeasonalPresets`, custom_numpad.dart:308-331).
Пользователь выбирает «С 25 апр — 40 %», шит честно пересчитывает нетто: 200 г брутто →
**120 г нетто**, показывает это на экране. Но в рецепт записывается продукт со **старым**
`wastePct = 20`, и бланк считает 200 × 0.8 = **160 г нетто**. Расхождение экрана и бланка — **33 %**.

**Воспроизведение** — [`audit_state_dialog_lifecycle_test.dart`](app/test/audit_state_dialog_lifecycle_test.dart):

```
DEFECT: a waste % typed in the sheet never reaches the ingredient added from SearchProductModal
  Expected: <40.0>   Actual: <20.0>
```
Контрольный тест с проброшенным колбэком даёт `wastePct = 40.0` — то есть дефект именно в no-op.
Воспроизводится и в редакторе ([recipe_editor_screen.dart:563](app/lib/presentation/screens/recipe_editor_screen.dart#L563)).

**Риск.** Самое опасное для «справки»: повар **видел** 120 г, а карта печатает 160 г. Блюдо
недосчитано по массе на 33 %, все нутриенты — тоже.

**Рекомендуемый патч.**

```dart
// _SearchProductModalState
Product? _pendingProduct;

// _buildInlineEditor
onProductUpdated: (updated) => setState(() => _pendingProduct = updated),
onConfirm: (grams, isGross) {
  _addToRecipe(_pendingProduct ?? product, grams, isGross);
  _pendingProduct = null;
},
```
Тот же паттерн — в `recipe_editor_screen.dart:563`.

---

## 🟠 GOST-02 — Одна глобальная тройка сохранности на любое блюдо

**Локализация.** [dish.dart:26-28](app/lib/core/calculation/models/dish.dart#L26-L28) (дефолт
`0.94 / 0.88 / 0.91`), [dish.dart:79-81](app/lib/core/calculation/models/dish.dart#L79-L81) (`fromJson`),
применяется на **итоги** в [calculation_engine.dart:32-38](app/lib/core/calculation/calculation_engine.dart#L32-L38).

**Сущность.**

Код:
$$\text{cooked} = \Big(\sum_i \text{raw}_i\Big) \times K_{сохр}$$

Правильно (Сборник, табл. «Потери при тепловой обработке», по видам обработки и по
группам сырья):
$$\text{cooked} = \sum_i \text{raw}_i \times K_{сохр}(\,процесс,\ группа_i\,)$$

Модель с **одним** триплетом физически не может выразить даже одно блюдо: в котлетной
массе мясо теряет 20/15/16 %, хлеб — 3,5/3,5/12 %, лук — 10/15/10 %.

**Воспроизведение** — [`audit_gost_yield_physics_test.dart`](app/test/audit_gost_yield_physics_test.dart):

```
B1: дефолт Dish ровно 0.94/0.88/0.91 для ЛЮБОГО блюда
B2: Оливье — приложение съедает 12 % жира и 9 % углеводов
    (Ж 30,11 → 34,22 г; У 12,82 → 14,09 г; ккал/100 г 155,2 → 173,7 → занижение −10,65 %)
B3: морс — тоже холодная технология: 9 % углеводов «испаряется»
B4 I7 Бульон (экстракция): норма 12,0/8,0/20,0 % — дефолт 94/88/91 % → Δ 683 / 1000 / 355 %
```

| Класс блюда | Норма | Дефолт | Δ |
|---|---|---|---|
| Варка супов | 93,5 / 91,7 / 91,8 % | 94/88/91 | 0,5 / **−4,0** / −0,9 % |
| Жарка основным способом | 80,0 / 85,0 / 84,0 % | 94/88/91 | **+17,5** / +3,5 / +8,3 % |
| Варка круп | 96,5 / 96,5 / 88,0 % | 94/88/91 | −2,6 / **−8,8** / +3,4 % |
| **Холодные блюда** | **100 / 100 / 100 %** | 94/88/91 | **−6,0 / −12,0 / −9,0 %** |
| Пар | 98,5 / 99,0 / 99,0 % | 94/88/91 | −4,6 / −11,1 / −8,1 % |
| **Бульон (экстракция)** | **12,0 / 8,0 / 20,0 %** | 94/88/91 | **+683 / +1000 / +355 %** |

**Риск.** Холодный салат, который повар **должен** считать без потерь БЖУ, занижается
на 10,7 % ккал и 12 % по жиру *по умолчанию*, если повар не догадается вручную поставить 100 %.
Бульон завышается в 10,8 раза по жиру — карта не проходит санитарную экспертизу.

**Патч.**

```dart
class Dish {
  final HeatProcess process;
  /// Сохранность по группам сырья, а не одна тройка на блюдо.
  final Map<FoodGroupId, LossTriplet> lossByGroup;
  LossTriplet defaultsFor(HeatProcess p) => switch (p) {
    HeatProcess.cold  => const LossTriplet(1.00, 1.00, 1.00),
    HeatProcess.soup  => const LossTriplet(0.935, 0.917, 0.918),
    HeatProcess.fry   => const LossTriplet(0.80, 0.85, 0.84),
    HeatProcess.grain => const LossTriplet(0.965, 0.965, 0.88),
    HeatProcess.stock => const LossTriplet(0.12, 0.08, 0.20),   // экстракция
    _                 => const LossTriplet(0.985, 0.99, 0.99),
  };
}
```
`Dish.fromJson` для старого документа без `process` — выводить процесс из набора
ингредиентов или помечать «процесс не задан» и **не** молчать.

---

## 🟠 STATE-04b / STATE-04c — Неудачная запись глушится, «сохранено» показывается зря

**Локализация.** [dish_provider.dart:198-213](app/lib/presentation/providers/dish_provider.dart#L198-L213)
(`_persist().catchError` ставит `lastPersistenceError`, но **никто в `lib/` его не читает**),
[dish_provider.dart:350-362](app/lib/presentation/providers/dish_provider.dart#L350-L362)
(`saveCurrentToLibrary`).

**Воспроизведение** — [`audit_state_dish_provider_test.dart`](app/test/audit_state_dish_provider_test.dart):

```
OBSERVED: a failing draft write is SWALLOWED by _persist(); flushPendingSaves() does not surface it either
  → lastPersistenceError = "disk full", но isDirty = false и данных на диске нет
DEFECT: saveCurrentToLibrary() also swallows the write failure
  → threw=(nothing), isDirty=false
```

**Риск.** «Диск полон» / каталог read-only / антивирус держит файл — повар уверен, что
рецепт сохранён, закрывает приложение, рецепта нет.

**Патч.** Сбрасывать `_lastCleanSnapshot` **только после успешной записи**; ошибку —
класть в состояние и показывать снекбар:
```dart
Future<void> _persist() {
  final snapshot = state;
  return _saveQueue = _saveQueue.then((_) async {
    await _savedDishesNotifier.updateDraftReference(snapshot);
    _lastCleanSnapshot = _contentSignature(snapshot);      // ← только при успехе
  }).catchError((Object e) {
    _lastPersistenceError = e;
    state = state.copyWith(persistError: e.toString());    // ← видимое поле
  });
}
```

---

## 🟠 IO-05 — Два экземпляра хранилища на одном каталоге теряют библиотеку

**Локализация.** [dish_storage_repository.dart:20](app/lib/data/repositories/dish_storage_repository.dart#L20) —
`Future<void> _tail` это поле **экземпляра**; [dish_storage_repository.dart:200-209](app/lib/data/repositories/dish_storage_repository.dart#L200-L209) —
общие имена `.tmp` / `.bak.tmp`.

**Воспроизведение** — [`audit_io_race_test.dart`](app/test/audit_io_race_test.dart):

```
IO-5/D-IO05 probe:  88 cross-instance I/O errors {OS32: 69, OS5: 15, OS2: 4}
                    disk ids [a59, b58] — ветка A потеряна
IO-5/D-IO05 probe2: 95 ошибок FileSystemException(2/32/5) на rename
IO-5/D-IO05 probe3: два полных ProviderContainer → fork библиотеки: disk=[fromB], A=(fromA)
```

**Риск.** `ProviderScope` на процесс один, поэтому **сейчас** дефект труднодостижим
(подтверждено STATE-05/I3: один экземпляр в графе). Но это «мина»: warm restart
Android/flutter engine в том же процессе, второй `ProviderContainer` в тестах или в
будущем мультиоконном режиме — и библиотека теряет ветку.

**Патч.** Файловая блокировка ОС + уникальные имена временных файлов:
```dart
Future<T> _withFileLock<T>(Future<T> Function() op) async {
  final dir = (await _getStorageFile())?.parent;
  if (dir == null) return op();
  await dir.create(recursive: true);
  final raf = await File(p.join(dir.path, '$_fileName.lock')).open(mode: FileMode.append);
  try { await raf.lock(); return await op(); }
  finally { await raf.unlock(); await raf.close(); }
}
// в saveAll: final temp = File('${file.path}.${_uniq()}.tmp');
```

---

## 🟠 MATH-05 — `customYield = 0,1 г` проходит валидацию → миллионы ккал на 100 г

**Локализация.** [calculation_validation.dart:46](app/lib/core/calculation/calculation_validation.dart#L46) —
`range(dish.customYieldGrams!, .1, 9999999, 'customYieldGrams')`.

**Сущность.** «На 100 г» = $\text{cooked} \times 100 / m_{вых}$. При $m_{вых} = 0{,}1$ г
и блюде на 1 кг коэффициент ×1000 завышает ЭЦ в 1000 раз. Сегодня этот вход ловится
**только побочно** гардом LOGIC-01 — то есть после починки LOGIC-01 дефект **станет живым**.

**Патч (обязателен в одном коммите с LOGIC-01).**
```dart
- range(dish.customYieldGrams!, .1, 9999999, 'customYieldGrams');
+ range(dish.customYieldGrams!, 1, 9999999, 'customYieldGrams');
```
Плюс запретить `yield < 0.01 × Σ нетто` предупреждением в UI.

---

## 🟠 FUZZ-13 — Автосохранение черновика переписывает всю библиотеку

**Локализация.** [dish_storage_repository.dart:182-212](app/lib/data/repositories/dish_storage_repository.dart#L182-L212):
`saveAll` сериализует **весь** массив блюд (`toJson` каждого), затем **перечитывает и
перепарсивает** файл ради `.bak` (после того как он уже прочитан), и делает **два**
`flush: true` (fsync).

**Измерено** — [`audit_fuzz_graph_memory_test.dart`](app/test/audit_fuzz_graph_memory_test.dart):

```
одно автосохранение черновика на библиотеке из 200 блюд: 723 мс и 1613 мс
документ 815 101 байт
профиль: toJson 30 + jsonEncode 35 + re-read/parse/CRC ~180 + fsync-I/O ~700 мс
```

**Риск.** Каждая цифра, нажатая в редакторе, ставит ввод в очередь за 0,7–1,6 с записи,
и это время растёт линейно с библиотекой. На ресторанной библиотеке в 500 блюд — секунды
на нажатие; телефон «задумывается» посреди кухни.

**Патч.** Разделить документы: `library.json` пишется только на `saveDish` / `deleteDish`;
`draft.json` — на каждое изменение, без `.bak` (черновик дешевле потерять, чем тормозить).
Плюс убрать двойное чтение: `previous` уже прочитан — отдать его в запись `.bak` из памяти.

---

## 🟠 IO-02 — Документ без `crc32` принимается как «legacy» → CRC обходится

**Локализация.** [dish_storage_repository.dart:132](app/lib/data/repositories/dish_storage_repository.dart#L132) —
`if (raw.containsKey('storageVersion') || raw.containsKey('crc32'))`: условие **ИЛИ**
означает «нет `crc32` → проверки нет».

**Воспроизведение** — [`audit_io_crc_backup_test.dart`](app/test/audit_io_crc_backup_test.dart):
```
observed: 'ПОДМЕНЁННОЕ БЛЮДО'          (подложенный «legacy» без crc32 принят)
expected: 'ПЕРВОЕ поколение'           (из .bak)
```

**Патч.** «Legacy» — однократный приём с маркером, а не по отсутствию ключа:
```dart
final looksModern = raw.containsKey('storageVersion') || raw.containsKey('crc32');
if (!looksModern) {
  final marker = File('${file.path}.legacy_seen');
  if (await marker.exists()) return null;      // повторная «legacy»-поставка — отказ
  await marker.writeAsString('1', flush: true);
}
```

---

## 🟠 IO-03 — Молчаливый откат на устаревший `.bak`; read-only main блокирует восстановление навсегда

**Воспроизведение** — [`audit_io_zerobyte_test.dart`](app/test/audit_io_zerobyte_test.dart):
```
IO-3/D-IO03 probe:  блюдо b исчезло: observed ['a'], expected ['b','a'] — без уведомления
IO-3/D-IO03 probe2: read-only main + битый → PathAccessException (errno 5) на каждом запуске,
                    хотя .bak валиден — данные целы, но недоступны
```

**Патч.** Возвращать данные `.bak` **в память**, даже если перезапись main не удалась, и
сигнализировать факт отката (`recoveredFromBackup`), чтобы UI показал баннер
«Библиотека восстановлена из резервной копии на <дата>».

---

## 🟡 FUZZ-11 / STATE-08 — Лимит 7 символов молча режет ввод

**Локализация.** [custom_numpad.dart:109](app/lib/presentation/widgets/custom_numpad.dart#L109) —
`else if (_currentInput.length < 7)`.

**Воспроизведение** — [`audit_fuzz_numpad_test.dart`](app/test/audit_fuzz_numpad_test.dart):

```
"12345,6" + "7" is SILENTLY dropped: readout "12345,6"   (не "12345,67")
"1234567" blocks the fraction: "1234567," — дробь набрать невозможно
```
При этом валидатор принимает до 9 999 999 г.

**Риск.** Повар набирает партию 12 345,67 г — получает 12 345,6 г, без звука, без подсказки,
без мигания. Бланк расходится с весами.

**Патч.** Лимит по формату, а не по длине, и обратная связь при отказе:
```dart
static final _mask = RegExp(r'^\d{0,7}(,\d{0,2})?$');
if (_mask.hasMatch(next)) { _currentInput = next; }
else { AppHaptics.warn(); _showDelta('Максимум 9 999 999 г, 2 знака'); }
```

---

## 🟡 MATH-02 — «Округление-затем-сумма» для ккал расходится с итогом на 1,0–1,6 ккал

**Локализация.** [ingredient.dart:74-75](app/lib/core/calculation/models/ingredient.dart#L74-L75)
(`blankKcalInDish` округляет `energy()` до 0,1 **на каждой строке**) +
[calculation_engine.dart:24-25](app/lib/core/calculation/calculation_engine.dart#L24-L25) (сумма уже
округлённых строк).

**Сущность.** Код: $\sum_i \text{round}_1(4P_i + 9F_i + 4C_i)$.
Правильно: $\text{round}_1(4\sum P_i + 9\sum F_i + 4\sum C_i)$.

**Воспроизведение** — [`audit_math_area_b_test.dart`](app/test/audit_math_area_b_test.dart) `B2.3`:
```
max recipe-vs-lines kcal gap: 1.0 (n=65 recipe=11111.0 lines=11112.0)
expected: ≤ 0.05
```
Растянутое подтверждение — `audit_math_numeric_edges_test.dart` `C2.1`: худший дрейф
**1.40 ккал**; на 4000 блюдах по 50–99 строк максимум **1,6 ккал**, и 3752 из 4000 случаев
превышают 0,01 ккал.

**Важно:** для Б/Ж/У инвариант «итог = сумма печатных строк» **держится** (проверено
`C2.2` и моим `LEAD-09`: `rows=16.09 total=16.09`). Расхождение есть **только** по ккал — потому
что там `energy()` округляется внутри строки, а сумма идёт по 4/9/4-пересчёту.

**Патч.** Считать итог «sum-then-round» от точных ячеек:
```dart
rawTotalKcal: CalculationMath.energy(rawTotalProtein, rawTotalFat, rawTotalCarbs),
```
(строки при этом продолжают печататься как есть, а итог **логически** согласован с итогами БЖУ).

---

## 🟡 MATH-03 — `waste = 100 %` молча превращает продукт в 0 г

**Локализация.** [ingredient.dart:22](app/lib/core/calculation/models/ingredient.dart#L22), [:42](app/lib/core/calculation/models/ingredient.dart#L42).

```
A1.5 waste = 100 is NOT silently zeroed (expects a throw) → observed: returned 0.0
A1.7 200 г брутто при 0 % нетто печатается как строка «0» в бланке
```

**Патч.** `waste = 100` — отсутствие съедобной части; исключать на входе:
```dart
if (wastePct >= 100.0) {
  throw ArgumentError.value(wastePct, 'wastePct',
      '100 % waste leaves no edible mass — product cannot be used');
}
// и в calculation_validation.dart:  range(p.wastePct, 0, 99.9, 'wastePct');
```

---

## 🟡 MATH-04 — Round-trip через *печатное* нетто при больших отходах дрейфует до 24 г

**Локализация.** [ingredient.dart:47-53](app/lib/core/calculation/models/ingredient.dart#L47-L53)
(`netGramsRounded` до 0,1 г) + переключение «Брутто | Нетто» в [custom_numpad.dart:146-167](app/lib/presentation/widgets/custom_numpad.dart#L146-L167),
которое берёт **печатное** значение.

```
A2.4 gross=245074.0 waste=99.8 netShown=490.1 back=245050.0 drift=24.0 g   (expected < 0.5)
```

**Важно:** чистый round-trip `gross→net→gross` через 12-значный путь **точен** (0 дрейфа на 30 000
случаях) — дефект исключительно в квантовании до 0,1 г на границе UI.

**Патч.** При отходах > 90 % показывать больше значащих цифр:
```dart
final convertedStr = _wastePct >= 90
    ? converted.toStringAsFixed(0)
    : CalculationEngine.formatGrams(converted);
```

---

## 🟡 MATH-08 — `retention = 0` допустим → правдоподобное «0,0 ккал»

```
B1.2 retention = 0 must not produce a valid-looking 0 kcal dish
  observed: cookedKcal 0.0, per100gKcal 0.0 для 1000 г говядины (rawTotalProtein 18.60)
  expected: > 0
```
Сохранность 0 % значит «не сохранилось ничего» — это не коэффициент, а ошибка ввода.
**Патч:** `range(r, 0.01, 1, 'retention')` в [calculation_validation.dart:43](app/lib/core/calculation/calculation_validation.dart#L43)
и `inRange(value, 0.01, 1)` в [dish_provider.dart:253](app/lib/presentation/providers/dish_provider.dart#L253).

---

## 🟡 FUZZ-01 — `kcal = NaN / ±Infinity / отрицательный` проходит валидацию

```
«product(kcal: Infinity) validates, kcalInDish -> Infinity»
«addIngredient ACCEPTS a product with kcal=Infinity»
  → сохранение падает: JsonUnsupportedObjectError: Converting object to an encodable object failed: Infinity
```
**Патч.** В `CalculationValidation.product()`:
```dart
range(p.kcal, 0, 100000, 'kcal');
range(p.water, 0, 1000, 'water');   // и fiber / sfa / pufa / chol / alcohol
```

---

## 🟡 IO-01 — Отходы заполнены у 12,7 % продуктов Скурихина (следствие Gold Master, не дефект кода)

**Сырые факты из `reference.db` (read-only):**

| Источник | Всего | С `waste_pct > 0` | Доля |
|---|---:|---:|---:|
| skurikhin | 1108 | **141** | **12,7 %** |
| bls | 7140 | 0 | 0 % |
| supplement | 13 | 0 | 0 % |
| **Итого** | **8261** | **141** | **1,7 %** |

Для всех ходовых продуктов Сборника отходы **есть** и верны: картофель 28 %, свёкла 20 %,
капуста 20 %, морковь 20 %, лук 16 %, говядина 25 %, яйцо 13 %, свинина 15 %. Поэтому типовой
учебный расчёт сходится. Но для остальных BLS-продуктов приложение молча считает
`waste = 0 %` — без предупреждения в UI и в экспорте.

**Правило проекта:** данные `reference.db` сертифицированы и **не меняются**. Поэтому
единственно верный патч — **в коде**, а не в данных:

```dart
// Product
bool get wasteIsKnown => source == 'skurikhin' && wastePct > 0;
// IngredientCard / BlankPreview / XLSX: пометка «отходы не заданы (0 %)»
```
Это закрывает «молчаливую» часть риска, не трогая Gold Master.

---

## 🟡 Дополнительно: карточки мастеров (`masters_recipes.dart`, данные приложения, не БД)

`masters_recipes.dart` — часть **кода**, а не `reference.db`, поэтому подлежит исправлению.

| Дефект | Число |
|---|---|
| Борщ `:116-119` — свёкла 200 г с `isGross: true` и `wastePct: 20` при рецептуре в нетто → **двойное списание** | Σ weight = 1368 г, Σ нетто = 1235,5 г, заявленный выход 1000 г |
| Каша `:279-309` — «100 г крупы + 150 г воды, выход 210 г»: приварок по массе фактически **200 %**, а в описании 110 % | 100+150+10 = 260 г → 210 г |
| Жарка `:332`, `:406` — `retentionFat: 0.95` при жарке физически невозможен (основной канал потерь — вытапливание, норма 0.85) | жир завышен на 11,8 % |
| Все карточки — `expectedYieldGrams` **не выводится** из рецептуры | борщ 1368→1000, котлеты 213→150, пюре 373→250 |
| `:135, :159, :183, :419` — справочная ЭЦ ≠ 4Б+9Ж+4У (Скурихин с усвояемостью) | капуста −3,9 %, морковь −3,7 %, томатная паста −6,7 %, творог −2,4 % |

**Данные о Б/Ж/У карточек сверены с `reference.db`:** 17 продуктов — **0 расхождений**.
Здесь виноват не Gold Master.

---

# 4. МАТРИЦА ЭТАЛОННЫХ ТЕХНОЛОГИЧЕСКИХ КАРТ

Метод: те же закладки, что в Сборнике, `customYieldGrams` = нормативный выход,
`retention` = 0.94/0.88/0.91 (дефолт приложения). Тест:
[`audit_gost_benchmark_test.dart`](app/test/audit_gost_benchmark_test.dart) (12 тестов).
Критерий: |Δ| > 2 % — FAILED, 1–2 % — WARNING.

| № | Блюдо | Выход норм (г) | Выход прил. (г) | Δ вых. | ккал/100 норм | ккал/100 прил. | Δ ккал | Вердикт |
|---|---|---:|---:|---:|---:|---:|---:|:--|
| I1 | Борщ сибирский с говядиной | 1000 | 1000 | 0,00 % | 40,0 | 39,7 | −0,75 % | ✅ **OK** |
| I2 | Котлеты домашние | 108 | 108 | 0,00 % | 279,2 | 298,0 | **+6,73 %** | ❌ **FAILED** |
| I3 | Каша гречневая рассыпчатая | 210 | 210 | 0,00 % | 111,0 | 108,1 | **−2,61 %** | ❌ **FAILED** |
| I4 | Картофельное пюре | 250 | 250 | 0,00 % | 149,6 | 136,5 | **−8,76 %** | ❌ **FAILED** |
| I5 | Салат «Оливье» | 250 | 250 | 0,00 % | 173,7 | 155,2 | **−10,65 %** | ❌ **FAILED** |
| I6 | Омлет натуральный паровой | 133,5 | 133,5 | 0,00 % | 156,0 | 141,0 | **−9,62 %** | ❌ **FAILED** |
| I7 | Куриный бульон прозрачный | 300 | 300 | 0,00 % | 10,8 | 30,7 | **+184,26 %** | ❌ **FAILED** |
| I8 | Сырники из творога | 140 | 140 | 0,00 % | 197,1 | 200,9 | +1,93 % | ⚠️ **WARNING** |
| I9 | Соус Бешамель | 1000 | 1000 | 0,00 % | 99,8 | 92,3 | **−7,52 %** | ❌ **FAILED** |
| I10 | Морс клюквенный | 1000 | 1000 | 0,00 % | 48,2 | 43,9 | **−8,92 %** | ❌ **FAILED** |

**Сходимость: 1 из 10.**
`Выход` совпадает везде **по построению** — он передан в `customYieldGrams` как есть. Это не
достоинство движка: это единственный способ, которым он вообще узнаёт выход. Если повар
выход не задал, ошибка становится такой (таблица из карточки GOST-01): **до −31,5 %** по ккал.

Б/Ж/У по блюдам:

| Блюдо | Белки | Жиры | Углеводы |
|---|---|---|---|
| I1 | 1,56 → 1,61 (+3,21 %) | 1,86 → 1,84 (−1,08 %) | 4,27 → 4,17 (−2,34 %) |
| I2 | 13,34 → 15,69 (+17,62 %) | 21,90 → 22,68 (+3,56 %) | 7,17 → 7,77 (+8,37 %) |
| I3 | 3,51 → 3,42 (−2,56 %) | 4,36 → 3,87 (−11,24 %) | 14,42 → 14,90 (+3,33 %) |
| I4 | 3,13 → 2,99 (−4,47 %) | 7,46 → 6,58 (−11,80 %) | 17,48 → 16,34 (−6,52 %) |
| I5 | 6,99 → 6,57 (−6,01 %) | 13,68 → 12,04 (−11,99 %) | 5,63 → 5,13 (−8,88 %) |
| I6 | 8,05 → 7,69 (−4,47 %) | 12,84 → 11,42 (−11,06 %) | 2,05 → 1,90 (−7,32 %) |
| I7 | 2,15 → 2,35 (+9,30 %) | 0,20 → 2,17 (**+985 %**) | 0,11 → 0,45 (**+309 %**) |
| I8 | 13,02 → 13,91 (+6,84 %) | 9,29 → 9,09 (−2,15 %) | 15,35 → 15,87 (+3,39 %) |
| I9 | 3,10 → 2,98 (−3,87 %) | 6,32 → 5,77 (−8,70 %) | 7,63 → 7,12 (−6,68 %) |
| I10 | 0,01 → 0,01 (0 %) | 0,00 → 0,00 | 12,05 → 10,97 (−8,96 %) |

---

# 5. КАТАЛОГ 68 КРИТЕРИЕВ АУДИТА

## 5.1. 20 базовых критериев (из ТЗ)

| № | Критерий | Статус | Улика |
|---:|---|:--:|---|
| 1 | Детерминизм до 10⁻⁹ | ✅ **PASSED** | 1000 прогонов бит-в-бит (`LEAD-08`, `C4.1`) |
| 2 | Инвариант массы $M_{вых} \le \sum M_{нетто}$ | ❌ **FAILED** | Гард *строже* физики на жире (LOGIC-01); вода суммируется без испарения (GOST-01) |
| 3 | Физическая неотрицательность | ⚠️ **WARNING** | Отрицательный `kcal` принимается (`FUZZ-04`); Б/Ж/У/массы — PASSED |
| 4 | Безопасность деления (нет NaN/Inf) | ✅ **PASSED** | Пустой рецепт → `0.0`; `NaN` → `ArgumentError` (`C3.1`, `FUZZ-01` таблица) |
| 5 | Точность IEEE 754, нет float-мусора | ✅ **PASSED** | `sumRounded(1000 × 0.1) == 100.0`; `49.999999999999994` не появляется |
| 6 | Консистентность ккал 4-9-4 | ⚠️ **WARNING** | `energy()` точен (11,7 млн точек), но итог ≠ сумма строк до 1,6 ккал (MATH-02) |
| 7 | Изоляция исходных данных (нет мутации Product в кэше) | ✅ **PASSED** | `copyWith` везде, `loadDishAsCopy` клонирует `Product.fromJson(toJson())` |
| 8 | Snapshot-независимость рецепта | ✅ **PASSED** | Подменённый до взрыва репозиторий не вызывается (`IO-9.p2`) |
| 9 | Брутто/Нетто — прямой и обратный расчёт | ✅ **PASSED** | 30 000 случаев, 0 дрейфа (`A2.1`, `A2.2`) |
| 10 | Дробные меры (1.5 ст., 0.25 ч.л.) | ✅ **PASSED** | `1,5 меры × 80 г = 120 г` (`STATE-12`) |
| 11 | Стрессоустойчивость I/O | ⚠️ **WARNING** | Битый main/`.bak`/zero-byte — восстановление есть; CRC обходится (IO-02) |
| 12 | Атомарность сохранения | ✅ **PASSED** | `.tmp` + fsync + rename; 50 циклов, 0 «сирот» (`IO-1.5`, `IO-1.6`) |
| 13 | Полнота очистки ресурсов | ⚠️ **WARNING** | 4 главных контроллера + `Transform` освобождаются; 2 в диалогах — нет (`STATE-07`) |
| 14 | Устойчивость к конкурентным изменениям | ✅ **PASSED** | 50 быстрых добавлений — все на диске (`STATE-09`) |
| 15 | Сложные составные блюда (полуфабрикаты) | ❌ **FAILED** | Только `Product.isDish`-метка; блюдо нельзя вставить ингредиентом (см. 5.2) |
| 16 | Коэффициенты уварки круп/макарон | ❌ **FAILED** | Модели нет вообще (GOST-01); гречка 1:2, рис 1:2,5, макароны 1:2 не заложены |
| 17 | Масштабирование на N порций ≤ 0,01 % | ✅ **PASSED** | `portion()` через точный `ratioRounded`, 123 456,7 г — конечно (`A3.5`) |
| 18 | Локализация чисел (запятая и точка) | ✅ **PASSED** | `"1,5"` → 1.5, `"1.5"` → 1.5, 33 входа без падений |
| 19 | Undo/Redo | ❌ **FAILED** | Стека нет; `restoreIngredient` без привязки к блюду (STATE-10a, STATE-10b) |
| 20 | Память и GC (100 рецептов) | ✅ **PASSED** | 200 create/delete — `state` и диск пусты, утечки нет |

## 5.2. 48 авторских критериев субагентов

| ID | Критерий | Статус | Улика |
|---|---|:--:|---|
| **A1** | Монотонность по массе ингредиента | ✅ PASSED | 5×200 случайных весов, 0 нарушений (`C3.1`) |
| **A2** | Монотонность по белку при фиксированном весе | ✅ PASSED | `C3.2` |
| **A3** | Сумма не зависит от порядка слагаемых | ✅ PASSED | `C4.2` |
| **A4** | Отсутствие float-дрейфа в `_sum` при 1000 слагаемых разных масштабов | ✅ PASSED | 2 мс, точно до последней цифры |
| **A5** | Нет OOM при `decimal` на экстремальных double | ✅ PASSED | `1e-300`, `4.9e-324`, `1e300` — без OOM |
| **A6** | HALF-UP корректен на полушагах | ✅ PASSED | `round1(0.25)=0.3`, `round2(1.005)=1.01` |
| **A7** | Печатные строки БЖУ суммируются в печатный итог | ✅ PASSED | `rows=16.09 total=16.09` (`LEAD-09`, `C2.2`) |
| **A8** | Печатные строки ккал суммируются в печатный итог | ❌ FAILED | дрейф до 1,6 ккал (MATH-02) |
| **B1** | Термодинамика: сухой остаток после уварки ≤ сумма сухого сырья | ✅ PASSED | БЖУ не растёт, растёт только концентрация — формула верна |
| **B2** | Термодинамика: вода не превращается в нутриенты | ✅ PASSED | `A3`-сценарий (нетто 600 → выход 1000): сумма БЖУ блюда не меняется |
| **B3** | Физически невозможный выход отклоняется | ✅ PASSED | `yield = 0.1 г` → отказ (но по неверной причине — см. MATH-05) |
| **B4** | Логически противоречивый выход — предупреждение, а не краш | ❌ FAILED | `ArgumentError` вместо предупреждения (LOGIC-01) |
| **B5** | Сохранность по классу обработки, а не одна тройка | ❌ FAILED | дефолт 0.94/0.88/0.91 для всего (GOST-02) |
| **B6** | Холодные блюда не теряют нутриенты по умолчанию | ❌ FAILED | Оливье −10,7 % ккал без действия пользователя |
| **B7** | Экстракция (бульон) моделируется отдельно | ❌ FAILED | +184 % по ккал (GOST-03) |
| **C1** | Парсинг: полная ширина цифр отвергается | ✅ PASSED | `"１２"` → null |
| **C2** | Парсинг: арабо-индийские цифры отвергаются | ✅ PASSED | `"١٢"` → null |
| **C3** | Парсинг: RTL-маркеры и ZWSP отвергаются | ✅ PASSED | `"\u200F12"`, `"\u200B12"` → null |
| **C4** | Парсинг: lone surrogate не крашит | ✅ PASSED | `parseInputDouble` и `jsonEncode` переживают |
| **C5** | Парсинг: экспонента не создаёт скрытый вес | ❌ FAILED | `"1e-7"` принят, напечатан как «0» (MATH-07) |
| **C6** | Парсинг: разделитель тысяч принимается | ❌ FAILED | `"1 000"` → null (FUZZ-07) |
| **C7** | Инъекции SQL/скриптов в названиях не исполняются | ✅ PASSED | Поиск идёт через FTS5 с параметрами; названия только рендерятся как текст |
| **D1** | Нумерация: «Итого» = сумма округлённых строк (бухгалтерская сверка) | ✅ PASSED | `LEAD-09` |
| **D2** | Нумерация: ккал итога сходится до 0,1 | ❌ FAILED | MATH-02 |
| **D3** | Калькуляционная карта: 2 знака после запятой в Б/Ж/У | ✅ PASSED | все хелперы `formatMacro` → 2 знака |
| **D4** | Калькуляционная карта: округление HALF-UP, а не banker's | ✅ PASSED | `productRounded` добавляет `+d` перед делением — HALF-UP |
| **E1** | Дебаунс поиска: 20 нажатий → 1 запрос | ✅ PASSED | `STATE-02(a)` |
| **E2** | Медленный репозиторий не перетирает новый запрос | ✅ PASSED | `STATE-02(b)` |
| **E3** | Смена фильтра во время поиска безопасна | ✅ PASSED | `STATE-02(c)` |
| **E4** | Таймер поиска отменяется на `dispose` | ✅ PASSED | `STATE-03` |
| **E5** | `isDirty` по контентной сигнатуре (8 сценариев) | ✅ PASSED | `STATE-04(a)-(h)` |
| **E6** | Двойной тап «Добавить» не теряет ингредиент | ✅ PASSED | `STATE-09` |
| **E7** | Правка до загрузки не теряет `isDirty` | ❌ FAILED | STATE-06a |
| **E8** | Правка до загрузки не затирает черновик на диске | ❌ FAILED | STATE-06b |
| **E9** | Неудачная запись — видима пользователю | ❌ FAILED | STATE-04b/c |
| **E10** | Расчёт вне диапазона не роняет экран | ❌ FAILED | STATE-01 |
| **E11** | Ручной % отходов доезжает до блюда | ❌ FAILED | STATE-11 |
| **F1** | Хранилище: CRC ловит любой одиночный битовый флип | ✅ PASSED | 30 флипов по всему документу — все обнаружены |
| **F2** | Хранилище: «legacy» нельзя подделать, убрав ключ | ❌ FAILED | IO-02 |
| **F3** | Хранилище: откат на `.bak` видим пользователю | ❌ FAILED | IO-03 |
| **F4** | Хранилище: read-only main не блокирует восстановление | ❌ FAILED | IO-03b |
| **F5** | Хранилище: первый save создаёт резервную копию | ❌ FAILED | IO-04 |
| **F6** | Хранилище: Unicode байт-в-байт (19 наборов) | ✅ PASSED | `IO-4` |
| **F7** | Хранилище: кросс-инстансная запись безопасна | ❌ FAILED | IO-05 |
| **F8** | Хранилище: нет тихого in-memory fallback | ❌ FAILED | IO-06 |
| **G1** | Производительность: 1000 ингредиентов < 2 с | ✅ PASSED | 517 мс прогретое |
| **G2** | Производительность: автосейв не зависит от размера библиотеки | ❌ FAILED | 723–1613 мс на 200 блюд (FUZZ-13) |
| **H1** | Полуфабрикат как ингредиент: нутриенты композируются верно | ❌ FAILED | вручную — верно, автоматически — невозможно (−24,3 %) |
| **H2** | Циклические зависимости исключены | ⚠️ WARNING | невозможно по модели (нет ссылок Dish→Dish), но это ограничение, а не защита |

**Итог по каталогу: 68 критериев — 39 PASSED (57 %), 22 FAILED (32 %), 7 WARNING (10 %).**

---

# 6. ПЛАН УСТРАНЕНИЯ ЗАМЕЧАНИЙ

## Этап 0 — Блокеры. Без них UI-этап не начинать (≈ 2–3 дня)

- [ ] **P0-1. Убрать гард LOGIC-01** и поднять нижнюю границу выхода (MATH-05) **одним коммитом**
      · `calculation_engine.dart:50-55`, `calculation_validation.dart:46`
      · Критерий приёмки: тесты `MATH-B3.1`, `B3.3`, `LEAD-01`, `LEAD-04` зелёные; `A3.2`, `A3.3` продолжают бросать.
- [ ] **P0-2. `calculationResultProvider` → `CalculationResult?` + баннер** (STATE-01)
      · `dish_provider.dart:31-34`, `recipe_editor_screen.dart:68`, `home_screen.dart:271,395`
      · Плюс `ErrorWidget.builder` в `main.dart`
      · Критерий: `LEAD-02`, все `STATE-01`-тесты зелёные; `ErrorWidget` не появляется.
- [ ] **P0-3. `PopScope`-эквивалент для «Новый расчёт»** (STATE-13) · `home_screen.dart`
- [ ] **P0-4. Починить восстановление черновика при ранней правке** (STATE-06b) · `dish_provider.dart:189-195`
- [ ] **P0-5. Ввести модель выхода: вода — через коэффициент поглощения, а не слагаемое** (GOST-01)
      · `dish.dart:35-43`, `calculation_engine.dart:16-17`
      · Критерий: каша 100 г крупы + 150 г воды → «Итого» не включает воду, выход по коэффициенту.

## Этап 1 — Критические. До начала UI-работы (≈ 2–3 дня)

- [ ] **P1-1. Пробросить `_pendingProduct`** из шита в `_addToRecipe` (STATE-11, MATH-09)
      · `search_product_modal.dart:480-483`, `recipe_editor_screen.dart:563`
- [ ] **P1-2. Сохранность по классу обработки** (GOST-02, GOST-03) · `dish.dart`, `masters_recipes.dart`
- [ ] **P1-3. Не глушить ошибку записи** (STATE-04b/c) · `dish_provider.dart:198-213, 350-362`
- [ ] **P1-4. Файловая блокировка + уникальные `.tmp`** (IO-05) · `dish_storage_repository.dart`
- [ ] **P1-5. Разделить `library.json` и `draft.json`** (FUZZ-13)
- [ ] **P1-6. «Legacy» с маркером + видимый откат на `.bak`** (IO-02, IO-03)

## Этап 2 — Существенные (≈ 2 дня)

- [ ] **P2-1. Лимит нумпада по формату + обратная связь** (FUZZ-11/STATE-08) · `custom_numpad.dart:109`
- [ ] **P2-2. Итог ккал = sum-then-round** (MATH-02) · `calculation_engine.dart:24-25`
- [ ] **P2-3. `waste = 100` и `retention = 0` отклонять** (MATH-03, MATH-08)
- [ ] **P2-4. `formatGrams` при отходах > 90 % — больше знаков** (MATH-04)
- [ ] **P2-5. `range(kcal/water/fiber/sfa/pufa/chol/alcohol)`** (FUZZ-01, FUZZ-04)
- [ ] **P2-6. Пометка «отходы не заданы» для продуктов без `waste_pct`** (IO-01) — **без изменения БД**
- [ ] **P2-7. `restoreIngredient(dishId)`** (STATE-10b)

## Этап 3 — Мелкие и архитектурные (≈ 1–2 дня)

- [ ] `MATH-06` guard `formatGrams` от int64-clamp и `Infinity`
- [ ] `MATH-07` отвергать экспоненту в `parseInputDouble` либо явный минимум 0,1 г
- [ ] `FUZZ-02` guard `decimal()` от `|v| > 1e15`
- [ ] `FUZZ-05/06` микродозы: «<0,1 г» вместо HALF-UP, сумма по точным значениям
- [ ] `FUZZ-07` разделитель тысяч, `FUZZ-08` отрицательные → null
- [ ] `FUZZ-09` guard `reorderIngredients` по длине
- [ ] `FUZZ-10` `setCustomYield` возвращает видимую ошибку
- [ ] `STATE-07` `dispose()` контроллеров диалогов
- [ ] `STATE-12` `formatGrams` в реад-ауте меры
- [ ] `IO-04` первый save создаёт `.bak`; `IO-06` убрать тихий in-memory; `IO-07` неизвестные ключи
- [ ] `STATE-10a` стек Undo/Redo + кнопки в AppBar
- [ ] `MATH-12/13` исправить карточки мастеров (двойное списание, `retentionFat: 0.95`)
- [ ] Полуфабрикаты как first-class (`Dish.parentDishId`, `Ingredient.dishRef`) — отдельная фича

## Этап 4 — Закрытие

- [ ] Вернуть базовую линию в зелёное: 24 красных теста → `tags: ['defect']` **после** починки
- [ ] `mega_io_fault_test.dart` 512 флипов × 30 с — пометить `@Tags(['heavy'])` или `Timeout.none`
- [ ] Прогнать весь набор в одну команду без таймаутов
- [ ] Целевой % PASSED по каталогу: **≥ 95 %** (сейчас 57 %)

---

# 7. ПРИЛОЖЕНИЕ А — Как воспроизвести аудит

```powershell
$env:PATH = "C:\projects\povarspravka\audit_artifacts\flutter-sdk\bin;" + $env:PATH
Set-Location C:\projects\povarspravka\app

# Только аудит-набор (31 файл): 433 пройдено / 24 красных
flutter test --concurrency=4 (Get-ChildItem test -Filter 'audit_*_test.dart').FullName

# Полный набор вместе с базовой линией: 583 пройдено / 24 красных
flutter test --concurrency=2
```

Замерено на момент сдачи отчёта:

| Прогон | Результат |
|---|---|
| Базовый набор (31 файл `audit_*_test.dart`) | **`+433 -24`** |
| Полный набор (50 файлов `*_test.dart`) | **`+583 -24`** |

**Все 24 падения — это аудит-тесты, воспроизводящие дефекты из раздела 3**, и ни один
из них не был красным до аудита. Базовая линия из 279 тестов до начала работы была
зелёной; после устранения этапов 0–2 все 24 станут зелёными **без правки самих тестов** —
они написаны как спецификация желаемого поведения, кроме явно помеченных тестов-«детектов»
(`[DEFECT IO-xx]`, `[DEFECT FUZZ-xx]`, `DEFECT: …`), которые после починки следует инвертировать.

## Состав аудита

| Субагент | Файлов | Тестов (заявлено) |
|---|---:|---:|
| `math-chemistry-auditor` | 3 | 41 |
| `gost-culinary-verifier` | 3 | 50 |
| `fuzzing-edge-hunter` | 5 | 161 |
| `persistence-fault-injector` | 12 | 67 |
| `state-concurrency-inspector` | 7 | 69 |
| Главный аудитор (кросс-проверки) | 1 | 10 |
| **Всего новых файлов** | **31** | — |

Раннер насчитывает **457** тестов против 398 в сумме заявленных субагентами: часть
файлов содержит циклы с `testWidgets`/`test` внутри `for`, и раннер разворачивает их
в отдельные кейсы. Цифра 457 — измеренная, счётчики субагентов — авторские.

## Состояние исходного кода

`app/lib/**` **и `app/assets/db/reference.db` аудитом не изменялись**.

`reference.db` открывалась исключительно через `sqlite3 ... ?mode=ro` (скрипт
`audit/logic_audit_20261030/db_probe.py`), mtime остался `30.10.2026 19:12` — до начала аудита.

По `app/lib/**` единственная запись в окне аудита — `dish_provider.dart` (mtime 20:48).
Субагент `state-concurrency-inspector` добавил туда геттер `savedDishesNotifierForTest`
для проверки графа провайдеров и **откатил** его тем же методом. Проверено:
`Select-String -Pattern 'savedDishesNotifierForTest'` по файлу даёт **0 совпадений**;
`git diff` по `lib/` не содержит этого изменения. Остальные 8 изменённых файлов в
`git status` по `lib/` — это **незакоммиченные правки, существовавшие до аудита**
(они зафиксированы в `docs/FINAL_LOGIC_SIGNOFF.md` как рабочее дерево на 2026-10-22).
