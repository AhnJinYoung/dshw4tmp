#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./search_test.sh [options]

Options (override defaults or set env vars):
  --array-size=INT               Number of elements per sample (default 10000)
  --trials=INT                   Trials per sample type (default 3)
  --random-min=INT               Minimum value for random samples (default -1000000)
  --random-max=INT               Maximum value for random samples (default 1000000)
  --dup-unique-fraction=FLOAT    Fraction of unique values in duplicate samples (default 0.05)
  --sorted-noise-fraction=FLOAT  Fraction of indices to shuffle in sorted samples (default 0.05)
  --timeout-seconds=FLOAT        Per-run timeout; abort and continue on expiry (default 10)
  --algorithms=LIST              Baseline algorithms (default Q,M,H,R)
  --trials-seed=INT              Random seed for reproducibility (default 1337)
  --java-command=PATH            Java executable (default java)
  --java-class=NAME              Target class (default SortingTest)
  --help
EOF
}

ARRAY_SIZE="${ARRAY_SIZE:-10000}"
TRIALS="${TRIALS:-3}"
RANDOM_MIN="${RANDOM_MIN:--1000000}"
RANDOM_MAX="${RANDOM_MAX:-1000000}"
DUP_UNIQUE_FRACTION="${DUP_UNIQUE_FRACTION:-0.05}"
SORTED_NOISE_FRACTION="${SORTED_NOISE_FRACTION:-0.05}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-10}"
ALGORITHMS_RUN="${ALGORITHMS_RUN:-Q,M,H,R}"
TRIALS_SEED="${TRIALS_SEED:-1337}"
JAVA_COMMAND="${JAVA_COMMAND:-java}"
JAVA_CLASS="${JAVA_CLASS:-SortingTest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --array-size=*) ARRAY_SIZE="${1#*=}";;
    --trials=*) TRIALS="${1#*=}";;
    --random-min=*) RANDOM_MIN="${1#*=}";;
    --random-max=*) RANDOM_MAX="${1#*=}";;
    --dup-unique-fraction=*) DUP_UNIQUE_FRACTION="${1#*=}";;
    --sorted-noise-fraction=*) SORTED_NOISE_FRACTION="${1#*=}";;
    --timeout-seconds=*) TIMEOUT_SECONDS="${1#*=}";;
    --algorithms=*) ALGORITHMS_RUN="${1#*=}";;
    --trials-seed=*) TRIALS_SEED="${1#*=}";;
    --java-command=*) JAVA_COMMAND="${1#*=}";;
    --java-class=*) JAVA_CLASS="${1#*=}";;
    --help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
  esac
  shift
done

if [[ ! -f "${JAVA_CLASS}.class" ]]; then
  echo "Compiling ${JAVA_CLASS}.java..."
  javac "${JAVA_CLASS}.java"
fi

export SCRIPT_DIR ARRAY_SIZE TRIALS RANDOM_MIN RANDOM_MAX
export DUP_UNIQUE_FRACTION SORTED_NOISE_FRACTION TIMEOUT_SECONDS
export ALGORITHMS_RUN TRIALS_SEED JAVA_COMMAND JAVA_CLASS

python3 - <<'PY'
import csv
import os
import random
import subprocess
import sys
import time
from pathlib import Path

script_dir = Path(os.environ["SCRIPT_DIR"])
array_size = int(os.environ["ARRAY_SIZE"])
trials = int(os.environ["TRIALS"])
random_min = int(os.environ["RANDOM_MIN"])
random_max = int(os.environ["RANDOM_MAX"])
dup_unique_fraction = float(os.environ["DUP_UNIQUE_FRACTION"])
sorted_noise_fraction = float(os.environ["SORTED_NOISE_FRACTION"])
timeout_seconds = float(os.environ["TIMEOUT_SECONDS"])
algorithms = [a.strip().upper() for a in os.environ["ALGORITHMS_RUN"].split(",") if a.strip()]
trials_seed = int(os.environ["TRIALS_SEED"])
java_command = os.environ["JAVA_COMMAND"]
java_class = os.environ["JAVA_CLASS"]

if array_size <= 0:
    raise ValueError("ARRAY_SIZE must be > 0.")
if trials <= 0:
    raise ValueError("TRIALS must be > 0.")
if random_min > random_max:
    raise ValueError("RANDOM_MIN must be <= RANDOM_MAX.")
if not (0.0 < dup_unique_fraction <= 1.0):
    raise ValueError("DUP_UNIQUE_FRACTION must be in (0, 1].")
if not (0.0 < sorted_noise_fraction <= 1.0):
    raise ValueError("SORTED_NOISE_FRACTION must be in (0, 1].")
if timeout_seconds <= 0:
    raise ValueError("TIMEOUT_SECONDS must be > 0.")
if not algorithms:
    raise ValueError("ALGORITHMS list cannot be empty.")

rng = random.Random(trials_seed)
output_dir = script_dir / "experiment_results"
output_dir.mkdir(exist_ok=True)
results_path = output_dir / "search_test_results.csv"

def build_random():
    return [rng.randint(random_min, random_max) for _ in range(array_size)]

def build_duplicates():
    unique_count = max(1, int(array_size * dup_unique_fraction))
    base_values = [rng.randint(random_min, random_max) for _ in range(unique_count)]
    values = [rng.choice(base_values) for _ in range(array_size)]
    rng.shuffle(values)
    return values

def build_sorted():
    values = sorted(rng.randint(random_min, random_max) for _ in range(array_size))
    swaps = max(1, int(array_size * sorted_noise_fraction))
    for _ in range(swaps):
        i = rng.randrange(array_size)
        j = rng.randrange(array_size)
        values[i], values[j] = values[j], values[i]
    return values

sample_generators = {
    "random": build_random,
    "high_duplicates": build_duplicates,
    "high_sortedness": build_sorted,
}

def run_java(array, commands):
    lines = [str(len(array))]
    lines.extend(str(v) for v in array)
    lines.extend(commands)
    if not commands or commands[-1] != "X":
        lines.append("X")
    payload = "\n".join(lines) + "\n"
    start = time.perf_counter()
    try:
        proc = subprocess.run(
            [java_command, java_class],
            input=payload.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=script_dir,
            timeout=timeout_seconds,
        )
        elapsed_ms = (time.perf_counter() - start) * 1000.0
        stdout_lines = proc.stdout.decode("utf-8", errors="ignore").splitlines()
        return elapsed_ms, stdout_lines, False
    except subprocess.TimeoutExpired:
        return timeout_seconds * 1000.0, [], True

def extract_algorithm(lines):
    for line in lines:
        stripped = line.strip()
        if stripped:
            return stripped[0]
    return None

results = []

for trial in range(1, trials + 1):
    print(f"=== Trial {trial}/{trials} ===")
    for sample_name, generator in sample_generators.items():
        data = generator()
        print(f"  Sample: {sample_name} (n={len(data)})")

        search_elapsed, search_lines, search_timeout = run_java(data, ["S", "X"])
        recommended = extract_algorithm(search_lines)
        if recommended not in algorithms:
            recommended = algorithms[0]
        search_notes = f"recommended={recommended}"
        combined_timeout = search_timeout
        total_elapsed = search_elapsed
        algo_elapsed = None
        if not search_timeout:
            algo_elapsed, _, algo_timeout = run_java(data, [recommended, "X"])
            combined_timeout = combined_timeout or algo_timeout
            total_elapsed += (0.0 if algo_elapsed is None else algo_elapsed)
            search_notes += f",algo_ms={algo_elapsed:.3f}"

        results.append(
            {
                "SampleType": sample_name,
                "Trial": trial,
                "Strategy": "Search+Recommend",
                "Algorithm": recommended,
                "ElapsedMs": round(total_elapsed, 6),
                "TimedOut": combined_timeout,
                "Details": f"search_ms={search_elapsed:.3f};{search_notes}",
            }
        )

        for algo in algorithms:
            elapsed, _, timed_out = run_java(data, [algo, "X"])
            results.append(
                {
                    "SampleType": sample_name,
                    "Trial": trial,
                    "Strategy": f"Always-{algo}",
                    "Algorithm": algo,
                    "ElapsedMs": round(elapsed, 6),
                    "TimedOut": timed_out,
                    "Details": "",
                }
            )

fieldnames = ["SampleType", "Trial", "Strategy", "Algorithm", "ElapsedMs", "TimedOut", "Details"]
with results_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row in results:
        writer.writerow(row)

print("Search-vs-baseline comparison saved to:", results_path)
PY
