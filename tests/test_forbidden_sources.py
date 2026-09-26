"""Licensing guard: the Falchi 2016 atlas and Lorenz atlas must never appear.

Both are license-contaminated (CC BY-NC; no license). If either name shows up
in pipeline code or configuration, the project becomes unusable — this test
fails the build before that can ship.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

FORBIDDEN = [
    "falchi",
    "world atlas of artificial night sky brightness",
    "new world atlas of artificial night sky brightness",
    "lorenz",
]

SCAN_ROOTS = ["pipelines", "config", ".github", "worker"]
SCAN_SUFFIXES = {".py", ".json", ".jsonc", ".toml", ".yml", ".yaml", ".csv", ".md", ".ts", ".js"}
SKIP_DIRS = {"node_modules", ".wrangler"}


def git_visible(root: Path) -> set[Path] | None:
    """Tracked plus untracked-but-not-ignored files; None when git is unavailable."""
    try:
        out = subprocess.run(
            [
                "git",
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "-z",
                "--",
                *SCAN_ROOTS,
            ],
            cwd=root,
            capture_output=True,
            check=True,
            text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return {(root / p).resolve() for p in out.split("\0") if p}


def repo_files() -> list[Path]:
    root = Path(__file__).parents[1]
    visible = git_visible(root)
    files: list[Path] = []
    for scan_root in SCAN_ROOTS:
        base = root / scan_root
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if SKIP_DIRS.intersection(path.relative_to(root).parts):
                continue
            if visible is not None and path.resolve() not in visible:
                continue
            if path.is_file() and (path.suffix.lower() in SCAN_SUFFIXES):
                files.append(path)
    return files


def test_no_forbidden_light_pollution_sources() -> None:
    offenders: list[str] = []
    for path in repo_files():
        text = path.read_text(errors="ignore").lower()
        for name in FORBIDDEN:
            # Allow mentions inside this guard itself and licensing docs.
            if name in text and "test_forbidden_sources" not in path.name:
                if path.name == "data-licensing.md":
                    continue
                offenders.append(f"{path.name}: contains '{name}'")
    assert not offenders, (
        "Forbidden data sources referenced (license contamination risk): " + "; ".join(offenders)
    )


def test_guard_scans_the_expected_roots() -> None:
    files = repo_files()
    assert any(p.suffix == ".py" for p in files)
    assert any(p.name == "app-config.json" for p in files)
    assert any(p.parts[-3:-1] == ("worker", "src") and p.suffix == ".ts" for p in files)
    assert not any(SKIP_DIRS.intersection(p.parts) for p in files)
