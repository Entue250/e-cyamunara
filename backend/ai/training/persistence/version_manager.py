"""
training/persistence/version_manager.py
========================================
Derives the next version string for a model by inspecting the live registry.

Version format:  vMAJOR.MINOR.PATCH-DATASOURCE  (e.g., "v1.0.0-synthetic")

Rules
-----
- First run for a datasource  → v1.0.0-{datasource}
- Subsequent runs             → bump PATCH of the highest existing version
  for the same datasource (both "registered" and "rejected" entries count,
  so every training attempt gets a unique, ordered identifier)
"""
from __future__ import annotations

import re

_VERSION_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)-(\S+)$")


def parse_version(version_str: str) -> tuple[int, int, int, str]:
    """Parse "v1.2.3-synthetic" → (1, 2, 3, "synthetic").

    Raises ValueError for non-conforming strings.
    """
    m = _VERSION_RE.match(version_str)
    if not m:
        raise ValueError(
            f"Version string {version_str!r} does not match vMAJOR.MINOR.PATCH-DATASOURCE"
        )
    return int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)


def format_version(major: int, minor: int, patch: int, datasource: str) -> str:
    """Build "vMAJOR.MINOR.PATCH-DATASOURCE"."""
    return f"v{major}.{minor}.{patch}-{datasource}"


def next_version(registry, model_name: str, datasource: str = "synthetic") -> str:
    """Return the next version string for *model_name* in *registry*.

    Parameters
    ----------
    registry:
        A ModelRegistry instance (needs only ``_load() -> dict``).
    model_name:
        One of "model_a", "model_b", "model_c".
    datasource:
        Datasource suffix, e.g. "synthetic" or "real".
    """
    reg_data = registry._load()
    versions: dict = (
        reg_data.get("models", {})
        .get(model_name, {})
        .get("versions", {})
    )

    same_ds = [v for v in versions if v.endswith(f"-{datasource}")]
    if not same_ds:
        return format_version(1, 0, 0, datasource)

    # Sentinel: (1, 0, -1) is beaten by any real v1.0.0
    best = (1, 0, -1)
    for v in same_ds:
        try:
            major, minor, patch, _ = parse_version(v)
            if (major, minor, patch) > best:
                best = (major, minor, patch)
        except ValueError:
            continue

    if best[2] == -1:
        # No parseable versions found despite non-empty same_ds
        return format_version(1, 0, 0, datasource)

    return format_version(best[0], best[1], best[2] + 1, datasource)
