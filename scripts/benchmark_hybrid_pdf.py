#!/usr/bin/env python3
"""Compare pinned MarkItDown and PDF Inspector without recording document content."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def package_version(python: Path, package: str) -> str:
    completed = subprocess.run(
        [
            str(python),
            "-c",
            "import importlib.metadata as m,sys;sys.stdout.write(m.version(sys.argv[1]))",
            package,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def run_once(command: list[str], output: Path) -> dict[str, object]:
    started = time.perf_counter()
    completed = subprocess.run(command, capture_output=True, text=True, timeout=120)
    elapsed_ms = (time.perf_counter() - started) * 1000
    output_data = output.read_bytes() if output.exists() else b""
    metadata: dict[str, object] = {}
    if completed.stdout.strip().startswith("{"):
        try:
            decoded = json.loads(completed.stdout)
            metadata = {
                key: decoded.get(key)
                for key in (
                    "schemaVersion",
                    "classification",
                    "pagesNeedingOCR",
                    "encodingSuspect",
                    "markdownWritten",
                )
            }
        except json.JSONDecodeError:
            metadata = {"stdout_json_valid": False}

    return {
        "elapsed_ms": round(elapsed_ms, 3),
        "exit_status": completed.returncode,
        "output_size": len(output_data),
        "output_sha256": sha256_bytes(output_data) if output_data else None,
        "stderr_sha256": (
            sha256_bytes(completed.stderr.encode("utf-8"))
            if completed.stderr
            else None
        ),
        "metadata": metadata,
    }


def benchmark_document(
    python: Path,
    helper: Path,
    source: Path,
    runs: int,
    work: Path,
) -> dict[str, object]:
    engines: dict[str, list[str]] = {
        "markitdown": [str(python), "-m", "markitdown", str(source), "-o"],
        "pdf-inspector": [str(python), str(helper), str(source)],
    }
    engine_results: dict[str, object] = {}
    for engine, prefix in engines.items():
        samples = []
        for index in range(runs):
            output = work / f"{source.stem}-{engine}-{index}.md"
            command = [*prefix, str(output)]
            samples.append(run_once(command, output))
        engine_results[engine] = {
            "median_elapsed_ms": round(
                statistics.median(sample["elapsed_ms"] for sample in samples),
                3,
            ),
            "samples": samples,
        }

    source_data = source.read_bytes()
    return {
        "source_name": source.name,
        "source_size": len(source_data),
        "source_sha256": sha256_bytes(source_data),
        "engines": engine_results,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run metadata-only PDF conversion benchmarks. The script never installs "
            "packages and never stores document or Markdown content in its report."
        )
    )
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument(
        "--helper",
        type=Path,
        default=Path("Resources/markitdown_pdf_inspector.py"),
    )
    parser.add_argument("--input", type=Path, action="append", required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--json-output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.runs < 1:
        raise SystemExit("--runs must be at least 1")
    for path in [args.python, args.helper, *args.input]:
        if not path.exists():
            raise SystemExit(f"Required path does not exist: {path}")

    with tempfile.TemporaryDirectory(prefix="mark-it-down-benchmark-") as temporary:
        documents = [
            benchmark_document(
                python=args.python,
                helper=args.helper,
                source=source,
                runs=args.runs,
                work=Path(temporary),
            )
            for source in args.input
        ]

    report = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "python": str(args.python),
        "packages": {
            "markitdown": package_version(args.python, "markitdown"),
            "pdf-inspector": package_version(args.python, "pdf-inspector"),
        },
        "runs_per_engine": args.runs,
        "documents": documents,
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.json_output:
        args.json_output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
