"""Pipeline runner for Skurikhin data extraction, validation, and database creation."""
import argparse
import sys
import time
from pathlib import Path
from typing import Dict, Any
import pymupdf

from .config import (
    DEFAULT_PDF_PATH,
    OUTPUT_DIR,
    DB_PATH,
    JSON_PATH,
    CSV_PATH,
    VALIDATION_REPORT_PATH
)
from .table_extractor import extract_all_products
from .validator import SkurikhinValidator
from .database_builder import (
    export_json,
    export_csv,
    build_sqlite_database,
    save_validation_report
)


def run_pipeline(pdf_path: Path = DEFAULT_PDF_PATH, output_dir: Path = OUTPUT_DIR) -> Dict:
    """Execute complete end-to-end data pipeline."""
    start_time = time.time()
    print("=" * 60)
    print("POVARSPRAVKA: SKURIKHIN 2002 DATA EXTRACTION PIPELINE")
    print(f"Source PDF: {pdf_path}")
    print(f"Output Dir: {output_dir}")
    print("=" * 60)

    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF file not found at: {pdf_path}")

    # Phase 1: Extraction
    print("\n[Phase 1/4] Extracting tables, Subject Index, and Appendices...")
    doc = pymupdf.open(str(pdf_path))
    products = extract_all_products(doc)
    print(f"  --> Extracted {len(products)} products across 12 food groups.")

    # Phase 2: Validation
    print("\n[Phase 2/4] Running Nutritional Physics & Chemistry Validation...")
    validator = SkurikhinValidator()
    report = validator.validate_dataset(products)
    print(f"  --> Quality Gate: {report['passed_products']} / {report['total_products']} passed ({report['pass_rate_pct']}%)")
    print(f"  --> Fatal errors: {report['fatal_errors']}, Duplicate codes: {report['duplicate_codes_count']}")
    print(f"  --> Avg Energy Delta: {report['quality_metrics']['avg_energy_difference_pct']}%")
    print(f"  --> Avg Proximate Mass: {report['quality_metrics']['avg_proximate_sum_grams']}g")

    # Phase 3: Exporting Datasets
    print("\n[Phase 3/4] Exporting Clean Datasets...")
    json_path = output_dir / "skurikhin_products.json"
    csv_path = output_dir / "skurikhin_products.csv"
    val_path = output_dir / "validation_report.json"
    db_path = output_dir / "reference.db"

    export_json(products, json_path)
    print(f"  --> Saved JSON: {json_path} ({json_path.stat().st_size / 1024:.1f} KB)")
    export_csv(products, csv_path)
    print(f"  --> Saved CSV:  {csv_path} ({csv_path.stat().st_size / 1024:.1f} KB)")
    save_validation_report(report, val_path)
    print(f"  --> Saved Report: {val_path}")

    # Phase 4: SQLite Reference DB with FTS5
    print("\n[Phase 4/4] Building SQLite Reference DB (FTS5 Search)...")
    build_sqlite_database(products, db_path)
    print(f"  --> Built DB: {db_path} ({db_path.stat().st_size / 1024:.1f} KB)")

    # Also deploy to Flutter app assets if present
    app_assets_db = Path("app/assets/db")
    if app_assets_db.exists():
        import shutil
        target_app_db = app_assets_db / "reference.db"
        shutil.copy2(str(db_path), str(target_app_db))
        print(f"  --> Deployed to Flutter assets: {target_app_db} ({target_app_db.stat().st_size / 1024:.1f} KB)")


    elapsed = time.time() - start_time
    print("\n" + "=" * 60)
    print(f"PIPELINE COMPLETED SUCCESSFULLY IN {elapsed:.2f}s!")
    print("=" * 60)

    return {
        "products_count": len(products),
        "validation_report": report,
        "db_path": str(db_path),
        "json_path": str(json_path),
        "csv_path": str(csv_path),
        "elapsed_seconds": round(elapsed, 2)
    }


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Skurikhin Data Extraction Pipeline")
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF_PATH, help="Path to Skurikhin PDF")
    parser.add_argument("--output", type=Path, default=OUTPUT_DIR, help="Output directory")
    args = parser.parse_args()

    run_pipeline(args.pdf, args.output)


if __name__ == "__main__":
    main()
