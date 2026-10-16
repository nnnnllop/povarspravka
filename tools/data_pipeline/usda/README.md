# USDA FoodData Central Data Pipeline (SR Legacy & Foundation Foods)

Production-ready offline ETL pipeline for processing, translating, validating, and formatting USDA FoodData Central (SR Legacy and Foundation Foods) datasets into SQLite databases conforming to `plan.md` Section 6.4 with full-text search (`FTS5`).

---

## 1. Overview & Capabilities

- **Source Dataset**: USDA FoodData Central SR Legacy (7,793 items) + Foundation Foods (387 items) = 8,180 items total.
- **Unified Reference Database**: Merges USDA items (`source = 'usda'`) with Skurikhin items (`source = 'skurikhin'`) into a unified `reference.db` (9,235 items total) matching `plan.md` Section 8.
- **Validation**: Enforces strict macronutrient bounds (0–100g), energy bounds (0–950 kcal), proximate bounds (sum ≤ 105g), missing energy imputation via Atwater factors, and Atwater formula plausibility.
- **Translation Engine**:
  - Translates all 28 SR Legacy food categories into Russian.
  - Translates product descriptions using cached culinary translations and targeted post-processing rules (correcting produce flesh/skin, buttermilk, giblets, sweet potatoes, hash browns, meat loaf, unbaked items, etc.).
  - Translates household measures and portion units (e.g., *1 cup* → *1 стакан*, *1 slice* → *1 ломтик*, *1 tbsp* → *1 ст. л.*).
- **Search & Normalization**:
  - Normalized fields (`ё` → `е`, lowercase, punctuation-free tokens).
  - Rich culinary synonym expansion (e.g., *картофель* ↔ *картошка*, *курица* ↔ *цыпленок / курятина*, *помидоры* ↔ *томаты*, *говядина* ↔ *телятина*).
  - Retains original English names for bilingual search queries.
  - SQLite FTS5 index with prefix matching and BM25 ranking (`unicode61 remove_diacritics 2`).

---

## 2. Pipeline Architecture & Directory Structure

```
tools/data_pipeline/usda/
├── __init__.py           # Package marker
├── config.py             # Paths, INFOODS nutrient codes, category mappings
├── fetcher.py            # SR Legacy & Foundation CSV/ZIP loaders & portions
├── validator.py          # Macronutrient ranges, proximate sum, and Atwater plausibility
├── translator.py         # Category, description, measure translation & synonyms
├── db_builder.py         # Canonical schema initialization, bulk loading, FTS5 & merge
├── pipeline.py           # End-to-end CLI orchestrator
├── inspect_db.py         # Verification and inspection utility
├── data/
│   ├── translation_cache.json    # Persistent translation cache
│   └── usda_vocab.json           # Distinct token frequencies
├── output/
│   ├── usda_products.db          # Standalone USDA database (FTS5 enabled)
│   ├── usda_catalog_manifest.json# Manifest metadata with counts & stats
│   └── validation_report.json    # Detailed validation summary and error logs
└── tests/
    ├── __init__.py
    ├── test_validator.py         # Unit tests for bounds, sums, error detection
    ├── test_translator.py        # Unit tests for translation, synonyms, normalization
    ├── test_db_builder.py        # Unit tests for canonical tables, FTS5, merge
    └── test_pipeline.py          # End-to-end integration test
```

---

## 3. SQLite Database Schema (Conforming to plan.md Section 6.4)

```sql
CREATE TABLE food_group (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL,
    name TEXT NOT NULL
);

CREATE TABLE product (
    id INTEGER PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    name_norm TEXT NOT NULL,
    group_id INTEGER NOT NULL REFERENCES food_group(id),
    source TEXT NOT NULL,
    page_num INTEGER,
    waste_pct REAL DEFAULT 0.0,
    protein REAL NOT NULL DEFAULT 0.0,
    fat REAL NOT NULL DEFAULT 0.0,
    carbs REAL NOT NULL DEFAULT 0.0,
    kcal REAL NOT NULL DEFAULT 0.0,
    water REAL NOT NULL DEFAULT 0.0,
    fiber REAL NOT NULL DEFAULT 0.0,
    ash REAL NOT NULL DEFAULT 0.0,
    organic_acids REAL NOT NULL DEFAULT 0.0,
    sugars REAL NOT NULL DEFAULT 0.0,
    starch REAL NOT NULL DEFAULT 0.0,
    sfa REAL NOT NULL DEFAULT 0.0,
    pufa REAL NOT NULL DEFAULT 0.0,
    chol REAL NOT NULL DEFAULT 0.0,
    alcohol REAL NOT NULL DEFAULT 0.0
);

CREATE TABLE measure (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES product(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    grams REAL NOT NULL
);

CREATE TABLE nutrient_value (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES product(id) ON DELETE CASCADE,
    nutrient_code TEXT NOT NULL,
    value REAL NOT NULL
);

CREATE TABLE synonym (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES product(id) ON DELETE CASCADE,
    synonym TEXT NOT NULL,
    synonym_norm TEXT NOT NULL
);

CREATE VIRTUAL TABLE product_fts USING fts5(
    product_id UNINDEXED,
    name,
    name_norm,
    tokenize = 'unicode61 remove_diacritics 2'
);
```

---

## 4. Usage & Execution

### Run Full Pipeline
```bash
python -m tools.data_pipeline.usda.pipeline
```

### CLI Options
- `--source <path>`: Custom path to USDA CSV directory or zip archive.
- `--output <path>`: Custom path for the output `.db` file.
- `--limit <N>`: Process only the first N items (for rapid testing).
- `--no-cache`: Disable updating translation cache.
- `--no-merge`: Do not merge USDA records into `reference.db`.

### Inspect and Verify Search
```bash
python tools/data_pipeline/usda/inspect_db.py
```

### Run Test Suite
```bash
python -m unittest discover -s tools/data_pipeline/usda/tests
```
