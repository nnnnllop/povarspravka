import sqlite3

con = sqlite3.connect('tools/data_pipeline/output/reference.db')
cur = con.cursor()
check_codes = ['8.1.4.1', '8.1.4.3', '8.1.4.17', '8.1.5.12', '8.1.5.24', '5.1.5', '10.8.1', '9.2.1.1', '1.6.4.3']
for c in check_codes:
    row = cur.execute("SELECT code, name, protein, fat, carbs, kcal, waste_pct FROM product WHERE code = ?", (c,)).fetchone()
    print(c, row[1].encode('unicode_escape').decode(), f"P={row[2]} F={row[3]} C={row[4]} kcal={row[5]} waste={row[6]}")

# Test FTS search on synonyms
syn_queries = ['картошка*', 'гречка*', 'геркулес*', 'курица*', 'свекла*']
print("\nTesting FTS synonym queries:")
for sq in syn_queries:
    res = cur.execute("SELECT p.code, p.name FROM product_fts fts JOIN product p ON p.id = fts.rowid WHERE product_fts MATCH ? LIMIT 2", (sq,)).fetchall()
    print(sq, [(r[0], r[1].encode('unicode_escape').decode()) for r in res])

con.close()
