"""Загрузка официальной базы BLS 4.0 (Bundeslebensmittelschlüssel).

Источник: https://www.blsdb.de/download — архив BLS 4.0 (декабрь 2025),
7 140 продуктов × 138 показателей, лицензия CC BY 4.0.

Скрипт идемпотентен: если архив и распакованные файлы уже на месте, ничего
не скачивается повторно (флаг --force заставляет перекачать).
"""
from __future__ import annotations

import io
import sys
import zipfile
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[3]        # ...\povarspravka
DATA = ROOT / "data" / "bls_v4"
RAW = DATA / "raw"
ZIP_PATH = RAW / "BLS_4_0_2025_DE.zip"

CANDIDATES = [
    "https://www.blsdb.de/download/BLS_4_0_2025_DE.zip",
    "https://www.blsdb.de/download",
]
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; povarspravka-bls/1.0)"}


def download(force: bool = False) -> Path:
    RAW.mkdir(parents=True, exist_ok=True)
    if ZIP_PATH.exists() and ZIP_PATH.stat().st_size > 1_000_000 and not force:
        print(f"архив уже есть: {ZIP_PATH} "
              f"({ZIP_PATH.stat().st_size / 1e6:.1f} МБ)")
        return ZIP_PATH
    last = None
    for url in CANDIDATES:
        try:
            print(f"качаю {url}")
            r = requests.get(url, headers=HEADERS, timeout=600, stream=True)
            r.raise_for_status()
            if "zip" not in (r.headers.get("content-type") or "") and \
                    not r.headers.get("content-type", "").startswith(
                        "application/octet-stream"):
                print(f"  пропускаю: content-type={r.headers.get('content-type')}")
                continue
            tmp = ZIP_PATH.with_suffix(".part")
            with tmp.open("wb") as fh:
                for chunk in r.iter_content(1 << 20):
                    fh.write(chunk)
            tmp.replace(ZIP_PATH)
            print(f"сохранено: {ZIP_PATH} "
                  f"({ZIP_PATH.stat().st_size / 1e6:.1f} МБ)")
            return ZIP_PATH
        except Exception as exc:                       # noqa: BLE001
            last = exc
            print(f"  ошибка: {exc}")
    raise RuntimeError(f"не удалось скачать архив BLS: {last}")


def unpack(path: Path | None = None) -> Path:
    path = path or ZIP_PATH
    if path.suffix != ".zip" or not zipfile.is_zipfile(path):
        raise RuntimeError(f"не архив BLS: {path}")
    target = RAW
    names = zipfile.ZipFile(path).namelist()
    print(f"в архиве файлов: {len(names)}")
    for n in names[:12]:
        print("  ", n)
    with zipfile.ZipFile(path) as zf:
        zf.extractall(target)
    # найти книгу данных
    books = sorted(target.rglob("BLS_4_0_Daten*.xlsx"))
    if not books:
        books = sorted(target.rglob("*.xlsx"))
    if not books:
        raise RuntimeError("в архиве нет .xlsx")
    print(f"книга данных: {books[0]}")
    return books[0]


def main() -> None:
    force = "--force" in sys.argv
    path = download(force)
    try:
        unpack(path)
    except RuntimeError as exc:
        print(exc)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    main()
