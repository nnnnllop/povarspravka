"""Кулинарный перевод названий BLS 4.0 на русский (DE/EN -> RU).

Требования:
  * модель deepseek-ai/DeepSeek-V4.1-Flash-1017 через api.river.ai;
  * пакеты по 40–50 продуктов, на входе code / name_de / name_en / category;
  * строгий JSON-массив [{bls_code, name_ru, synonyms_ru[1..3]}];
  * каждый ответ дописывается в data/bls_v4/translations_cache.jsonl —
    повторный запуск продолжает с места остановки;
  * 8 потоков, повторы с экспоненциальной паузой.
"""
from __future__ import annotations

import json
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "data" / "bls_v4"
CACHE = DATA / "translations_cache.jsonl"
RAW_XLSX = DATA / "raw" / "BLS_4_0_2025_DE" / "BLS_4_0_Daten_2025_DE.xlsx"

URL = "https://api.river.ai/v1/chat/completions"
API_KEY_ENV = "RIVER_API_KEY"
MODEL = "deepseek-ai/DeepSeek-V4.1-Flash-1017"

BATCH = 44
WORKERS = 8
LOCK = threading.Lock()


def _api_key() -> str:
    key = os.environ.get(API_KEY_ENV, "").strip()
    if not key:
        raise RuntimeError(
            f"Не задана переменная окружения {API_KEY_ENV} для доступа к {URL}"
        )
    return key


SYSTEM = (
    "Ты — профессиональный переводчик кулинарной и товароведческой "
    "терминологии. Переводишь наименования продуктов из немецкой базы "
    "пищевой ценности BLS 4.0 на русский язык. Отвечай строго JSON-массивом "
    "без пояснений и markdown."
)


def ask(prompt: str, retries: int = 6) -> str:
    api_key = _api_key()
    body = {"model": MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 8000, "temperature": 0}
    last = None
    for attempt in range(retries):
        try:
            r = requests.post(URL, json=body, timeout=300,
                              headers={"Authorization": f"Bearer {api_key}"})
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"]
        except Exception as exc:                       # noqa: BLE001
            last = exc
            time.sleep(2 + attempt * 5)
    raise RuntimeError(f"LLM недоступен: {last}")


def extract_json(text: str):
    start = text.find("[")
    end = text.rfind("]")
    if start < 0 or end <= start:
        return None
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return None


def load_products() -> list[dict]:
    import openpyxl

    import mapping as MP
    wb = openpyxl.load_workbook(RAW_XLSX, read_only=True, data_only=True)
    ws = wb[wb.sheetnames[0]]
    rows = ws.iter_rows(values_only=True)
    head = next(rows)
    i_code = head.index("BLS Code")
    i_de = head.index("Lebensmittelbezeichnung")
    i_en = head.index("Food name")
    out = []
    for r in rows:
        code = (r[i_code] or "").strip()
        if not code:
            continue
        out.append({"code": code,
                    "name_de": (r[i_de] or "").strip(),
                    "name_en": (r[i_en] or "").strip(),
                    "category": MP.category_of(code)})
    return out


def cache_load() -> dict[str, dict]:
    done: dict[str, dict] = {}
    if not CACHE.exists():
        return done
    for line in CACHE.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        for item in rec.get("data") or []:
            code = str(item.get("bls_code") or "").strip()
            if code:
                done[code] = item
    return done


def cache_append(batch: list[dict], data: list[dict]) -> None:
    with LOCK:
        with CACHE.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({"batch": [b["code"] for b in batch],
                                 "data": data}, ensure_ascii=False) + "\n")


def prompt_for(batch: list[dict]) -> str:
    lines = [json.dumps({"bls_code": b["code"], "name_de": b["name_de"],
                         "name_en": b["name_en"], "category": b["category"]},
                        ensure_ascii=False) for b in batch]
    return (
        SYSTEM + "\n\nПереведи наименования продуктов на русский язык.\n"
        "Правила:\n"
        "- name_ru — естественное русское название продукта так, как его "
        "называют в магазине и в кулинарии (не калька с немецкого);\n"
        "- сохраняй важные уточнения: степень обработки (сырой, варёный, "
        "консервированный, копчёный), жирность, сорт, часть туши;\n"
        "- немецкие названия видов рыб, сыров, сортов хлеба передавай "
        "принятыми в русском языке названиями (Heilbutt -> палтус, "
        "Matjes -> матье/сельдь слабосолёная);\n"
        "- synonyms_ru — 1–3 коротких синонима, как этот продукт ещё называют "
        "или ищут (строчными буквами, без кавычек);\n"
        "- переводи ВСЕ строки, ничего не пропускай и не добавляй.\n\n"
        "Формат ответа: [{\"bls_code\": \"...\", \"name_ru\": \"...\", "
        "\"synonyms_ru\": [\"...\"]}, ...]\n\n"
        "Продукты:\n" + "\n".join(lines)
    )


def translate_batch(batch: list[dict]) -> list[dict]:
    text = ask(prompt_for(batch))
    data = extract_json(text) or []
    wanted = {b["code"] for b in batch}
    clean = []
    for item in data:
        if not isinstance(item, dict):
            continue
        code = str(item.get("bls_code") or "").strip()
        name = str(item.get("name_ru") or "").strip()
        if code not in wanted or not name:
            continue
        syn = item.get("synonyms_ru") or []
        if isinstance(syn, str):
            syn = [syn]
        syn = [str(s).strip().strip("«»\"'").lower() for s in syn if str(s).strip()]
        clean.append({"bls_code": code, "name_ru": name,
                      "synonyms_ru": syn[:3]})
    return clean


def main() -> None:
    _api_key()
    DATA.mkdir(parents=True, exist_ok=True)
    products = load_products()
    print(f"продуктов в BLS: {len(products)}")
    done = cache_load()
    print(f"уже переведено (кэш): {len(done)}")
    todo = [p for p in products if p["code"] not in done]
    print(f"к переводу: {len(todo)}")
    chunks = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]
    print(f"пакетов: {len(chunks)} по {BATCH}")

    def work(chunk: list[dict]) -> int:
        for attempt in range(3):
            try:
                data = translate_batch(chunk)
            except Exception as exc:                   # noqa: BLE001
                print(f"  ! пакет {chunk[0]['code']}: {exc}", flush=True)
                time.sleep(5)
                continue
            if data:
                cache_append(chunk, data)
                return len(data)
            time.sleep(3)
        return 0

    total = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for i, n in enumerate(pool.map(work, chunks), 1):
            total += n
            if i % 10 == 0 or i == len(chunks):
                print(f"  пакетов {i}/{len(chunks)}, переведено {total}",
                      flush=True)
    done = cache_load()
    print(f"итого в кэше: {len(done)} из {len(products)}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    main()
