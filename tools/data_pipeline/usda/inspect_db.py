"""Standalone DB inspection script."""

import sqlite3
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

db_path = Path(__file__).resolve().parent / "output" / "usda_products.db"
print("Database path:", db_path)
print("Database size:", round(db_path.stat().st_size / (1024 * 1024), 2), "MB")

conn = sqlite3.connect(str(db_path))
cur = conn.cursor()

print("\nTable counts:")
for t in ["food_group", "product", "nutrient_value", "measure", "synonym", "product_fts"]:
    cnt = cur.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
    print(f"  {t:15s}: {cnt}")

print("\nSample 5 Products:")
for row in cur.execute("SELECT id, code, name, kcal, protein, fat, carbs FROM product LIMIT 5").fetchall():
    print(f"  [{row[0]}] ({row[1]}) {row[2]} | {row[3]} kcal (Б:{row[4]}, Ж:{row[5]}, У:{row[6]})")

print("\nSample FTS5 Queries:")
queries = ["картошка", "помидоры", "куриная", "говяжий фарш", "пахта", "salmon", "beef"]
for q in queries:
    search_term = q + "*"
    res = cur.execute(
        """
        SELECT p.id, p.name, p.kcal
        FROM product_fts f
        JOIN product p ON f.product_id = p.id
        WHERE product_fts MATCH ?
        ORDER BY rank
        LIMIT 2
        """,
        (search_term,),
    ).fetchall()
    print(f"Query '{q}':")
    for r in res:
        print(f"   -> [{r[0]}] {r[1]} ({r[2]} ккал)")

conn.close()
