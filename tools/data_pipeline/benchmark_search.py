"""Бенчмарк поиска по справочнику: 101 запрос, тот же SQL, что в приложении.

Зачем отдельный инструмент. README обещает «мгновенный полнотекстовый поиск
SQLite FTS5 (< 15–20 мс)», но до этапа 6.6 эту цифру никто не мерил: в
тестах проверялась только ПРАВИЛЬНОСТЬ выдачи (что нашлось), а не время.
Бенчмарк закрывает пункт Мега-Аудита №5 о замере 101 запроса.

Что именно измеряется. Не `build_reference_db.search` (упрощённый
«контрольный» поиск), а ПОЛНЫЙ путь `ProductRepository._ftsSearch`:

  1. два прохода FTS5 — ТОЧНАЯ форма (как написано, без `*`) и УСЕЧЁННАЯ
     основа (`"сырок"*`), если первый проход не набрал лимит;
  2. ранжирование ровно как в Dart (`is_dish ASC`, «целое слово» в
     названии/синониме, начало слова, подстрока, Скурихин выше BLS, bm25,
     длина названия);
  3. пакетная загрузка мер продуктов одним запросом (без N+1);
  4. при пустой выдаче — LIKE-fallback по `name_norm` и `synonym`.

Корпус — 101 запрос (запрос №101 — латинский `chicken`):
  * 20 односложных частых («картошка», «молоко», «гречка», …);
  * 20 составных и с цифрами («молоко 3.2», «сметана 10», «масло 82.5»);
  * 20 бытовых, где нужен синоним («сало», «спагетти», «ньокки», «рибай»);
  * 20 из аудита №4/№5 и новые для этапа 6.6 («окорочок куриный»,
    «филе индейки», «говяжий», «свиная»);
  * 20 «тяжёлых»: короткие префиксы (`сыр`, `со`, `я`), где FTS5 обязан
    перебрать тысячи кандидатов, и пустые хвосты (`щщщ`, `zzz`);
  * 1 латинский.

Порог. Ожидание `< 20 мс` на запрос берётся в режиме калькулятора
(`is_dish = False`) — это режим модалки поиска сырья; допускается
не больше `SLOW_ALLOWED` запросов сверх порога (первый запрос в процессе
греет страницы БД и кэш, поэтому один «медленный» — ожидаемый).

Запуск:
    python -X utf8 tools/data_pipeline/benchmark_search.py
    python -X utf8 tools/data_pipeline/benchmark_search.py --json out.json
    python -X utf8 tools/data_pipeline/benchmark_search.py --no-threshold
"""
from __future__ import annotations

import argparse
import json
import math
import sqlite3
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "app" / "assets" / "db" / "reference.db"

# Порог отклика одного запроса (README: «< 15–20 мс»).
LIMIT_MS = 20.0
# Сколько запросов допустимо медленнее порога (прогрев страниц/кэша).
SLOW_ALLOWED = 1
# Сколько раз повторить весь корпус (берётся медиана по прогонам).
ROUNDS = 3

# 101 реальный кулинарный запрос шеф-повара (выровнен с CHEF_101_BENCHMARK).
try:
    from test_audit_regressions import CHEF_101_BENCHMARK
    QUERIES: tuple[str, ...] = tuple(q for q, _ in CHEF_101_BENCHMARK)
except ImportError:
    from tools.data_pipeline.test_audit_regressions import CHEF_101_BENCHMARK
    QUERIES: tuple[str, ...] = tuple(q for q, _ in CHEF_101_BENCHMARK)

# Зеркало `_vowels` / `_fleeting` из ProductRepository._stemToken.
_VOWELS = "аеёиоуыэюяйь"
_FLEETING = "оеё"


def normalize_query(text: str) -> str:
    """То же, что `ProductRepository._normalizeQuery` в Dart."""
    low = (text or "").lower().replace("ё", "е")
    cleaned = "".join(ch if (ch.isalnum() or ch.isspace()) else " "
                      for ch in low)
    return " ".join(cleaned.split())


def stem_token(token: str) -> str:
    """Зеркало `ProductRepository._stemToken` (цикл по окончанию)."""
    if len(token) <= 3:
        return token
    if len(token) > 4 and token[-2] in _FLEETING and token.endswith("к"):
        return token[:-2] + "к"
    while len(token) > 3 and token[-1] in _VOWELS:
        token = token[:-1]
    return token


# SQL дословно из `ProductRepository._ftsSearch` (упрощён только `p.*`,
# чтобы не тянуть 23 колонки на каждый результат: на время FTS5 это не
# влияет, но держит память бенчмарка предсказуемой).
FTS_SQL = """
  SELECT p.id
  FROM product_fts fts
  JOIN product p ON p.id = CAST(fts.product_id AS INTEGER)
  WHERE product_fts MATCH ?
  ORDER BY
    p.is_dish ASC,
    CASE
      WHEN p.name_norm = ? THEN 0
      WHEN (' ' || p.name_norm || ' ') LIKE ? THEN 1
      WHEN (' ' || fts.name_norm || ' ') LIKE ? THEN 2
      WHEN p.name_norm LIKE ? THEN 3
      WHEN p.name_norm LIKE ? THEN 4
      ELSE 5
    END ASC,
    CASE WHEN p.name_norm LIKE ? THEN 0 ELSE 1 END ASC,
    CASE WHEN p.source = 'skurikhin' THEN 0 ELSE 1 END,
    bm25(product_fts, 10.0, 1.0) ASC,
    LENGTH(p.name) ASC
  LIMIT ?
"""

FALLBACK_SQL = """
  SELECT p.id FROM product p
  WHERE (p.name_norm LIKE ? OR EXISTS (
    SELECT 1 FROM synonym s
    WHERE s.product_id = p.id
      AND (s.synonym_norm LIKE ? OR LOWER(s.synonym) LIKE ?)
  ))
  {dish_sql}
  ORDER BY p.is_dish ASC,
           CASE WHEN p.source = 'skurikhin' THEN 0 ELSE 1 END,
           LENGTH(p.name) ASC, p.name ASC
  LIMIT ?
"""

MEASURES_SQL = "SELECT id, product_id, name, grams FROM measure " \
               "WHERE product_id IN ({}) ORDER BY id ASC"


def run_query(conn: sqlite3.Connection, query: str, limit: int = 50,
              is_dish: bool | None = False) -> list[int]:
    """Один поиск так, как его делает приложение; возвращает id продуктов."""
    clean = normalize_query(query)
    tokens = [stem_token(t) for t in clean.split()]
    exact_tokens = clean.split()
    first_pass_exact = all(len(t) >= 4 for t in exact_tokens)
    match_exact = " ".join(f'"{t}"' if first_pass_exact else f'"{t}"*'
                           for t in exact_tokens)
    match_stem = " ".join(f'"{t}"*' for t in tokens)
    dish = None if is_dish is None else (1 if is_dish else 0)
    dish_sql = "" if dish is None else " AND p.is_dish = ?"
    db_dish_args = () if dish is None else (dish,)
    order_args = [clean, f"% {clean} %", f"% {clean} %", f"{clean} %",
                  f"%{clean}%", f"%{clean}%", limit]
    sql = FTS_SQL.replace("WHERE product_fts MATCH ?",
                          "WHERE product_fts MATCH ?" + dish_sql)

    ids: list[int] = []
    if clean:
        ids = [r[0] for r in conn.execute(
            sql, [match_exact, *db_dish_args, *order_args])]
        if len(ids) < limit and match_stem != match_exact:
            seen = set(ids)
            for row in conn.execute(sql, [match_stem, *db_dish_args,
                                          *order_args]):
                if row[0] not in seen:
                    seen.add(row[0])
                    ids.append(row[0])
                if len(ids) >= limit:
                    break
    if not ids and clean:  # LIKE-fallback одинаков для пустого ответа
        pattern = f"%{clean}%"
        args = [pattern, pattern, pattern]
        if dish is not None:
            args.append(dish)
        args.append(limit)
        ids = [r[0] for r in conn.execute(FALLBACK_SQL.format(dish_sql=dish_sql), args)]
    if not ids:
        return []
    # пакетная загрузка мер (без N+1), как в ProductRepository
    placeholders = ",".join("?" * len(ids))
    list(conn.execute(MEASURES_SQL.format(placeholders), ids))
    return ids


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[rank]


def benchmark(db_path: Path, queries: tuple[str, ...] = QUERIES,
              rounds: int = ROUNDS, limit_ms: float = LIMIT_MS) -> dict:
    conn = sqlite3.connect(f"file:{db_path.as_posix()}?mode=ro", uri=True)
    try:
        # Прогрев: поднять страницы БД в page cache, чтобы не мерить I/O.
        list(conn.execute("SELECT COUNT(*) FROM product_fts"))
        per_query: dict[str, list[float]] = {q: [] for q in queries}
        empty: set[str] = set()
        for _round in range(rounds):
            for query in queries:
                started = time.perf_counter()
                ids = run_query(conn, query)
                elapsed_ms = (time.perf_counter() - started) * 1000.0
                per_query[query].append(elapsed_ms)
                if not ids:
                    empty.add(query)
        timings = {q: statistics.median(v) for q, v in per_query.items()}
        values = list(timings.values())
        return {
            "db": str(db_path),
            "products": conn.execute(
                "SELECT COUNT(*) FROM product").fetchone()[0],
            "queries": len(queries),
            "rounds": rounds,
            "total_ms": round(sum(values), 3),
            "mean_ms": round(statistics.fmean(values), 3),
            "median_ms": round(statistics.median(values), 3),
            "p95_ms": round(percentile(values, 0.95), 3),
            "max_ms": round(max(values), 3),
            "slow": sorted(
                ((round(ms, 3), q) for q, ms in timings.items()
                 if ms > limit_ms), reverse=True),
            "empty": sorted(empty),
            "timings": {q: round(ms, 3) for q, ms in timings.items()},
        }
    finally:
        conn.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--json", type=Path, default=None,
                        help="куда записать полный отчёт")
    parser.add_argument("--rounds", type=int, default=ROUNDS)
    parser.add_argument("--limit-ms", type=float, default=LIMIT_MS)
    parser.add_argument("--no-threshold", action="store_true",
                        help="не падать на медленных запросах (только отчёт)")
    args = parser.parse_args(argv)

    result = benchmark(args.db, QUERIES, max(1, args.rounds), limit_ms=args.limit_ms)
    print(f"бенчмарк поиска: {result['queries']} запросов × "
          f"{result['rounds']} прогонов")
    print(f"  база: {result['products']} продуктов, "
          f"{Path(result['db']).stat().st_size / 1048576:.2f} МБ")
    print(f"  медиана на запрос: {result['median_ms']:.2f} мс")
    print(f"  среднее:           {result['mean_ms']:.2f} мс")
    print(f"  p95:               {result['p95_ms']:.2f} мс")
    print(f"  максимум:          {result['max_ms']:.2f} мс")
    print(f"  всего (сумма):     {result['total_ms']:.1f} мс")
    if result["empty"]:
        print(f"  пустой ответ у {len(result['empty'])}: "
              f"{', '.join(result['empty'][:10])}")
    slow = [item for item in result["slow"]]
    if slow:
        print("  медленнее порога:")
        for ms, query in slow[:10]:
            print(f"    {ms:6.2f} мс  «{query}»")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, ensure_ascii=False, indent=2),
                             encoding="utf-8")
        print(f"  отчёт: {args.json}")

    # Гейт оценивает p95 (не должен превышать limit_ms) и число аномалий (допускается SLOW_ALLOWED).
    p95_ok = result["p95_ms"] <= args.limit_ms
    slow_ok = len(slow) <= SLOW_ALLOWED
    if (not p95_ok or not slow_ok) and not args.no_threshold:
        print(f"  ! Порог {args.limit_ms:.0f} мс превышен: p95={result['p95_ms']:.2f} мс (порог {args.limit_ms:.0f} мс), "
              f"медленных={len(slow)} (допускается {SLOW_ALLOWED})")
        return 1
    print(f"  порог {args.limit_ms:.0f} мс: OK "
          f"(p95: {result['p95_ms']:.2f} мс, медленнее порога: {len(slow)}, допускается {SLOW_ALLOWED})")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    raise SystemExit(main())
