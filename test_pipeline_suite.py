"""Expose the maintained pipeline suite to `python -m unittest discover` at root."""
from pathlib import Path
import unittest


def load_tests(loader, tests, pattern):
    root = Path(__file__).resolve().parent
    suite = loader.discover(str(root / 'tools' / 'data_pipeline'), pattern='test*.py', top_level_dir=str(root))
    if suite.countTestCases() == 0:
        raise RuntimeError('Pipeline discovery unexpectedly found zero tests')
    return suite
