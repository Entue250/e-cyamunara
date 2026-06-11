"""
training/run_all_models.py
==========================
Train, version, persist, and register all three E-CYAMUNARA ML models
in sequence (A → B → C).

Exit code: 0 if all three pass acceptance, 1 if any model fails.

Usage:
    python -m training.run_all_models
    python -m training.run_all_models --data /path/to/auctions.csv
    python -m training.run_all_models --datasource real
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from training import run_model_a, run_model_b, run_model_c

_RUNNERS = [
    ("model_a", run_model_a.run),
    ("model_b", run_model_b.run),
    ("model_c", run_model_c.run),
]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train and register all three E-CYAMUNARA ML models"
    )
    parser.add_argument(
        "--data",
        type=pathlib.Path,
        default=None,
        help="Path to auctions CSV (default: CONFIG.paths.synthetic_auctions)",
    )
    parser.add_argument(
        "--datasource",
        default="synthetic",
        help="Datasource label written to registry and history (default: synthetic)",
    )
    args = parser.parse_args()

    results: dict[str, bool] = {}
    for name, runner in _RUNNERS:
        print(f"\n{'=' * 62}")
        print(f"  {name}")
        print(f"{'=' * 62}")
        results[name] = runner(data_path=args.data, datasource=args.datasource)

    print(f"\n{'=' * 62}")
    print("  Summary")
    print(f"{'=' * 62}")
    all_passed = True
    for name, passed in results.items():
        status = "PASSED" if passed else "FAILED"
        print(f"  {name:<10}  {status}")
        if not passed:
            all_passed = False

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
