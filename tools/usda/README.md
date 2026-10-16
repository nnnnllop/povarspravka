# USDA FoodData Central Parser, Translator & Normalizer

Инструмент загрузки, фильтрации, перевода и нормализации базы данных USDA FoodData Central (SR Legacy + Foundation Foods).

## Структура директорий

```
c:\projects\povarspravka\
├── data\usda\
│   ├── products_usda.json         # Итоговая нормализованная база в формате JSON (8 180 продуктов)
│   └── products_usda.csv          # Итоговая база в формате CSV (с UTF-8 BOM для Excel)
└── tools\usda\
    ├── download_datasets.py       # Скачивание и распаковка SR Legacy и Foundation Foods архивов
    ├── translator.py              # Модуль перевода, нормализации и SQLite-кэширования
    ├── polish_translations.py     # Постобработка кулинарных терминов и тонкостей русского языка
    ├── build_database.py          # Основной конвейер сборки базы данных
    └── cache\
        ├── sr_legacy.zip          # Исходный архив SR Legacy (6.1 МБ)
        ├── foundation.zip         # Исходный архив Foundation Foods (3.3 МБ)
        ├── translations_cache.db  # Персистентный SQLite кэш переводов (8 180 записей)
        ├── sr_legacy\             # Распакованные CSV USDA SR Legacy
        └── foundation\            # Распакованные CSV USDA Foundation Foods
```

## Источники данных

- **SR Legacy (Standard Reference Legacy)**: 7 793 выверенных эталонных продукта питания.
- **Foundation Foods**: 387 базовых цельных продуктов питания (без лабораторных промежуточных суб-образцов).
- **Итого**: 8 180 уникальных натуральных и базовых продуктов питания без брендового мусора (UPC candy bars, chips, fast-food snacks с штрихкодами исключены).

## Извлекаемые параметры на 100 г

| Поле | Тип | Nutrient ID | Описание |
|------|-----|-------------|----------|
| `fdc_id` | `int` | - | Уникальный идентификатор USDA FoodData Central |
| `name_ru` | `string` | - | Нормализованное наименование на русском языке |
| `name_en` | `string` | - | Исходное наименование USDA |
| `category` | `string` | - | Пищевая категория / группа продуктов (25 категорий) |
| `kcal` | `float` | 1008 | Энергетическая ценность (ккал на 100 г) |
| `protein` | `float` | 1003 | Белки (г на 100 г) |
| `fat` | `float` | 1004 | Жиры (г на 100 г) |
| `carbs` | `float` | 1005 | Углеводы по разности (г на 100 г) |
| `water` | `float` | 1051 | Вода (г на 100 г) |
| `fiber` | `float` | 1079 | Клетчатка / пищевые волокна (г на 100 г) |

## Запуск конвейера

1. **Скачивание исходных CSV:**
   ```bash
   python tools/usda/download_datasets.py
   ```

2. **Сборка, автовалидация и перевод базы данных:**
   ```bash
   python tools/usda/build_database.py
   ```

3. **Кулинарная постобработка и полировка терминов:**
   ```bash
   python tools/usda/polish_translations.py
   ```

Благодаря локальному SQLite кэшу в `tools/usda/cache/translations_cache.db` повторный запуск конвейера занимает считанные секунды.
