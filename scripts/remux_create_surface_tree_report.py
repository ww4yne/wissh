#!/usr/bin/env python3
"""Summarize Remux create-surface-tree callback phase timings."""

from __future__ import annotations

import argparse
import re
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path


BEGIN_RE = re.compile(
    r"registry\.runtimeCreateSurfaceTree begin "
    r"nodes=(?P<nodes>\d+) leaves=(?P<leaves>\d+)"
)
PHASE_RE = re.compile(
    r"registry\.runtimeCreateSurfaceTree\.phase "
    r"phase=(?P<phase>[^ ]+) "
    r"elapsed_ms=(?P<elapsed>[0-9.]+) "
    r"total_ms=(?P<total>[0-9.]+)"
    r"(?P<fields>.*)$"
)
END_RE = re.compile(
    r"registry\.runtimeCreateSurfaceTree end "
    r"leaves=(?P<leaves>\d+) "
    r"focused=(?P<focused>[^ ]+) "
    r"elapsed_ms=(?P<elapsed>[0-9.]+)"
    r"(?P<fields>.*)$"
)
FIELD_RE = re.compile(r" (?P<key>[A-Za-z0-9_]+)=(?P<value>[^ ]+)")


@dataclass
class CreateSurfaceTreeSample:
    source: str
    line: int
    nodes: int | None = None
    leaves: int | None = None
    top_levels: int | None = None
    managed: int | None = None
    elapsed_ms: float | None = None
    phases: dict[str, float] = field(default_factory=dict)

    @property
    def phase_total_ms(self) -> float:
        return sum(self.phases.values())

    @property
    def residual_ms(self) -> float | None:
        if self.elapsed_ms is None:
            return None
        return self.elapsed_ms - self.phase_total_ms


def parse_fields(raw: str) -> dict[str, str]:
    return {match.group("key"): match.group("value") for match in FIELD_RE.finditer(raw)}


def parse_logs(paths: list[Path]) -> list[CreateSurfaceTreeSample]:
    samples: list[CreateSurfaceTreeSample] = []
    current: CreateSurfaceTreeSample | None = None

    for path in paths:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for line_number, line in enumerate(handle, start=1):
                if "Remux latency" not in line:
                    continue

                if begin := BEGIN_RE.search(line):
                    current = CreateSurfaceTreeSample(
                        source=str(path),
                        line=line_number,
                        nodes=int(begin.group("nodes")),
                        leaves=int(begin.group("leaves")),
                    )
                    continue

                if phase := PHASE_RE.search(line):
                    if current is None:
                        current = CreateSurfaceTreeSample(source=str(path), line=line_number)
                    current.phases[phase.group("phase")] = float(phase.group("elapsed"))
                    fields = parse_fields(phase.group("fields"))
                    if "nodes" in fields:
                        current.nodes = int(fields["nodes"])
                    if "leaves" in fields:
                        current.leaves = int(fields["leaves"])
                    if "topLevels" in fields:
                        current.top_levels = int(fields["topLevels"])
                    if "managed" in fields:
                        current.managed = int(fields["managed"])
                    continue

                if end := END_RE.search(line):
                    if current is None:
                        current = CreateSurfaceTreeSample(source=str(path), line=line_number)
                    current.leaves = int(end.group("leaves"))
                    current.elapsed_ms = float(end.group("elapsed"))
                    fields = parse_fields(end.group("fields"))
                    if "topLevels" in fields:
                        current.top_levels = int(fields["topLevels"])
                    elif "topCount" in fields:
                        current.top_levels = int(fields["topCount"])
                    if "managed" in fields:
                        current.managed = int(fields["managed"])
                    samples.append(current)
                    current = None

    return samples


def summarize(values: list[float]) -> str:
    if not values:
        return "count=0"
    return (
        f"count={len(values)} total_ms={sum(values):.3f} "
        f"avg_ms={statistics.fmean(values):.3f} max_ms={max(values):.3f}"
    )


def print_report(samples: list[CreateSurfaceTreeSample]) -> None:
    print(f"createSurfaceTree samples={len(samples)}")
    totals = [sample.elapsed_ms for sample in samples if sample.elapsed_ms is not None]
    print(f"callback {summarize(totals)}")

    phase_names = sorted({name for sample in samples for name in sample.phases})
    if not phase_names:
        print("phase data: missing")
    else:
        for phase in phase_names:
            print(
                f"phase.{phase} "
                f"{summarize([sample.phases[phase] for sample in samples if phase in sample.phases])}"
            )
        residuals = [sample.residual_ms for sample in samples if sample.residual_ms is not None]
        print(f"phase.residual {summarize(residuals)}")

    slowest = sorted(
        [sample for sample in samples if sample.elapsed_ms is not None],
        key=lambda sample: sample.elapsed_ms or 0,
        reverse=True,
    )[:10]
    if not slowest:
        return

    columns = ["rank", "elapsed", "leaves", "nodes", "top", "managed", *phase_names, "residual"]
    print("slowest " + " ".join(columns))
    for rank, sample in enumerate(slowest, start=1):
        residual = sample.residual_ms
        values = [
            str(rank),
            f"{sample.elapsed_ms:.3f}" if sample.elapsed_ms is not None else "na",
            str(sample.leaves) if sample.leaves is not None else "na",
            str(sample.nodes) if sample.nodes is not None else "na",
            str(sample.top_levels) if sample.top_levels is not None else "na",
            str(sample.managed) if sample.managed is not None else "na",
            *[f"{sample.phases[name]:.3f}" if name in sample.phases else "na" for name in phase_names],
            f"{residual:.3f}" if residual is not None else "na",
        ]
        print("slowest " + " ".join(values))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path, help="Unified log text files to parse")
    args = parser.parse_args(argv)

    missing = [path for path in args.logs if not path.exists()]
    if missing:
        for path in missing:
            print(f"missing log: {path}", file=sys.stderr)
        return 2

    print_report(parse_logs(args.logs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
