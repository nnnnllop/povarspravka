"""Parser for Subject Index (pages 211-234) of Skurikhin 2002 book.

Extracts official product codes, clean hierarchical product names, and page references
using indentation-based tree traversal.
"""
from typing import Dict, List, Optional
import re
import pymupdf


def normalize_code(raw_code: str) -> Optional[str]:
    """Clean and extract standardized product code like '1.1.2.2' or '9.1.1.3'."""
    if not raw_code:
        return None
    raw_code = raw_code.strip()
    m = re.search(r'(\d+(?:\.\d+)+|\d+)', raw_code)
    if not m:
        return None
    code = m.group(1)
    return code


def parse_subject_index(doc: pymupdf.Document, start_page: int = 211, end_page: int = 234) -> List[Dict]:
    """Parse all pages of the Subject Index and return list of products."""
    products = []
    seen_codes = set()

    root_parent = ""
    sub_parent = ""

    for pno in range(start_page, end_page + 1):
        page = doc[pno]
        words = page.get_text("words")

        # Cluster words into lines by Y coordinate
        lines = []
        for w in words:
            matched = False
            for line in lines:
                if abs(line[0][1] - w[1]) < 3.5:
                    line.append(w)
                    matched = True
                    break
            if not matched:
                lines.append([w])

        lines.sort(key=lambda l: l[0][1])

        for line in lines:
            line.sort(key=lambda w: w[0])
            line_y = line[0][1]
            if line_y < 35 or line_y > 680:
                continue

            name_words = [w[4] for w in line if w[0] < 360]
            code_words = [w[4] for w in line if 360 <= w[0] < 450]
            pg_words = [w[4] for w in line if w[0] >= 450]

            name_str = " ".join(name_words).strip()
            code_str = " ".join(code_words).strip()
            pg_str = " ".join(pg_words).strip()

            if not name_str or name_str in ["ПРЕДМЕТНЫЙ УКАЗАТЕЛЬ", "Пищевой продукт"]:
                continue

            # Single capital letter heading (А, Б, В, ...)
            if len(name_str) == 1 and name_str.isupper():
                root_parent = ""
                sub_parent = ""
                continue

            code = normalize_code(code_str)
            indent = line[0][0]
            cleaned = re.sub(r'^[-\~–—\s]+', '', name_str).strip()

            # Heading without code
            if not code:
                if indent < 85:
                    root_parent = cleaned
                    sub_parent = ""
                else:
                    sub_parent = cleaned
                continue

            # Item with code
            name_parts = []
            if indent < 85:
                # Top level item with its own code (e.g. Агар 10.11.1)
                root_parent = cleaned
                sub_parent = ""
                name_parts = [cleaned]
            elif 85 <= indent < 115:
                # Sub-item under root_parent
                name_parts = [root_parent, cleaned] if root_parent else [cleaned]
            else:
                # Sub-sub-item under sub_parent
                parts = [p for p in [root_parent, sub_parent, cleaned] if p]
                name_parts = parts

            # Deduplicate repeated words in hierarchy
            full_tokens = []
            for part in name_parts:
                for tok in part.split():
                    if not full_tokens or tok.lower() != full_tokens[-1].lower():
                        full_tokens.append(tok)
            full_name = " ".join(full_tokens).strip()

            page_num = 0
            if pg_str:
                m_pg = re.search(r'\d+', pg_str)
                if m_pg:
                    page_num = int(m_pg.group(0))

            prod_item = {
                "code": code,
                "name": full_name,
                "short_name": cleaned,
                "root_category": root_parent,
                "page_index": page_num,
                "source_index_page": pno,
            }
            products.append(prod_item)
            seen_codes.add(code)

    return products


if __name__ == "__main__":
    import sys
    from .config import DEFAULT_PDF_PATH
    sys.stdout.reconfigure(encoding="utf-8")
    doc = pymupdf.open(str(DEFAULT_PDF_PATH))
    prods = parse_subject_index(doc)
    print(f"Extracted {len(prods)} products from Subject Index.")
    for p in prods[:15]:
        print(f"  [{p['code']}] {p['name']} (p. {p['page_index']})")
