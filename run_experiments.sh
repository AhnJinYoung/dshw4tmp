#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage: ./run_experiments.sh [options]

Options (override defaults; otherwise set environment variables):
  --array-size=INT
  --min-samples=INT
  --max-samples=INT
  --max-half-width-ms=FLOAT
  --max-half-width-relative=FLOAT
  --confidence=FLOAT
  --java-command=PATH
  --java-class=NAME
  --algorithms=LIST             (comma-separated e.g. I,Q,M,H,R)
  --digit-ks=LIST               (comma-separated integers)
  --duplicate-ratios=LIST       (comma-separated floats)
  --sorted-ratios=LIST          (comma-separated floats)
  --size-experiment-arrays=LIST (comma-separated ints for array-size sweep)
  --duplicate-tolerance=FLOAT
  --sorted-tolerance=FLOAT
  --random-seed=INT
  --runs-per-sample=INT         (repetitions per generated dataset)
  --warmup-runs=INT             (per-algorithm warmup executions)
  --help
EOF
}

ARRAY_SIZE="${ARRAY_SIZE:-10000}"
MIN_SAMPLES="${MIN_SAMPLES:-8}"
MAX_SAMPLES="${MAX_SAMPLES:-40}"
MAX_HALF_WIDTH_MS="${MAX_HALF_WIDTH_MS:-0.5}"
MAX_HALF_WIDTH_RELATIVE="${MAX_HALF_WIDTH_RELATIVE:-0.05}"
CONFIDENCE="${CONFIDENCE:-0.95}"
JAVA_COMMAND="${JAVA_COMMAND:-java}"
JAVA_CLASS="${JAVA_CLASS:-SortingTest}"
ALGORITHMS="${ALGORITHMS:-I,Q,M,H,R}"
DIGIT_KS="${DIGIT_KS:-1,2,3,4,5,6,7,8,9}"
DUPLICATE_RATIOS="${DUPLICATE_RATIOS:-AUTO}"
SORTED_RATIOS="${SORTED_RATIOS:-AUTO}"
DUPLICATE_TOLERANCE="${DUPLICATE_TOLERANCE:-0.02}"
SORTED_TOLERANCE="${SORTED_TOLERANCE:-0.02}"
RANDOM_SEED="${RANDOM_SEED:-12345}"
RUNS_PER_SAMPLE="${RUNS_PER_SAMPLE:-3}"
WARMUP_RUNS="${WARMUP_RUNS:-2}"
SIZE_EXPERIMENT_ARRAYS="${SIZE_EXPERIMENT_ARRAYS:-100000,500000,1000000}"
RUN_DIGIT_EXPERIMENT="${RUN_DIGIT_EXPERIMENT:-1}"
RUN_DUPLICATE_EXPERIMENT="${RUN_DUPLICATE_EXPERIMENT:-1}"
RUN_SORTED_EXPERIMENT="${RUN_SORTED_EXPERIMENT:-1}"
RUN_SIZE_EXPERIMENT="${RUN_SIZE_EXPERIMENT:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --array-size=*) ARRAY_SIZE="${1#*=}";;
    --min-samples=*) MIN_SAMPLES="${1#*=}";;
    --max-samples=*) MAX_SAMPLES="${1#*=}";;
    --max-half-width-ms=*) MAX_HALF_WIDTH_MS="${1#*=}";;
    --max-half-width-relative=*) MAX_HALF_WIDTH_RELATIVE="${1#*=}";;
    --confidence=*) CONFIDENCE="${1#*=}";;
    --java-command=*) JAVA_COMMAND="${1#*=}";;
    --java-class=*) JAVA_CLASS="${1#*=}";;
    --algorithms=*) ALGORITHMS="${1#*=}";;
    --digit-ks=*) DIGIT_KS="${1#*=}";;
    --duplicate-ratios=*) DUPLICATE_RATIOS="${1#*=}";;
    --sorted-ratios=*) SORTED_RATIOS="${1#*=}";;
    --size-experiment-arrays=*) SIZE_EXPERIMENT_ARRAYS="${1#*=}";;
    --duplicate-tolerance=*) DUPLICATE_TOLERANCE="${1#*=}";;
    --sorted-tolerance=*) SORTED_TOLERANCE="${1#*=}";;
    --random-seed=*) RANDOM_SEED="${1#*=}";;
    --runs-per-sample=*) RUNS_PER_SAMPLE="${1#*=}";;
    --warmup-runs=*) WARMUP_RUNS="${1#*=}";;
    --help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
  esac
  shift
done

if [[ ! -f "${JAVA_CLASS}.class" ]]; then
  echo "Compiling ${JAVA_CLASS}.java..."
  javac "${JAVA_CLASS}.java"
fi

export SCRIPT_DIR ARRAY_SIZE MIN_SAMPLES MAX_SAMPLES MAX_HALF_WIDTH_MS
export MAX_HALF_WIDTH_RELATIVE CONFIDENCE JAVA_COMMAND JAVA_CLASS
export ALGORITHMS DIGIT_KS DUPLICATE_RATIOS SORTED_RATIOS SIZE_EXPERIMENT_ARRAYS
export DUPLICATE_TOLERANCE SORTED_TOLERANCE RANDOM_SEED
export RUNS_PER_SAMPLE WARMUP_RUNS
export RUN_DIGIT_EXPERIMENT RUN_DUPLICATE_EXPERIMENT RUN_SORTED_EXPERIMENT RUN_SIZE_EXPERIMENT

python3 - <<'PY'
import csv
import json
import math
import os
import random
import statistics
import subprocess
import sys
import time
from decimal import Decimal, getcontext
from collections import defaultdict
from pathlib import Path

script_dir = Path(os.environ["SCRIPT_DIR"])

getcontext().prec = 8

def parse_int(name):
    return int(os.environ[name])

def parse_float(name):
    return float(os.environ[name])

def parse_list(name, cast):
    raw = os.environ.get(name, "")
    parts = [part.strip() for part in raw.split(",") if part.strip()]
    return [cast(part) for part in parts]

def parse_positive_int(name):
    value = int(os.environ[name])
    if value <= 0:
        raise ValueError(f"{name} must be > 0.")
    return value

def parse_nonnegative_int(name):
    value = int(os.environ[name])
    if value < 0:
        raise ValueError(f"{name} must be >= 0.")
    return value

def parse_bool(name, default=True):
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"0", "false", "off", "no", ""}

def build_sequence(start, stop, step, decimals=2):
    values = []
    current = Decimal(str(start))
    stop_dec = Decimal(str(stop))
    step_dec = Decimal(str(step))
    quantize = Decimal("1").scaleb(-decimals)
    while current <= stop_dec + Decimal("1e-9"):
        values.append(float(current.quantize(quantize)))
        current += step_dec
    return values

base_array_size = parse_int("ARRAY_SIZE")
min_samples = parse_int("MIN_SAMPLES")
max_samples = parse_int("MAX_SAMPLES")
max_half_width_ms = parse_float("MAX_HALF_WIDTH_MS")
max_half_width_relative = parse_float("MAX_HALF_WIDTH_RELATIVE")
confidence = parse_float("CONFIDENCE")
java_command = os.environ["JAVA_COMMAND"]
java_class = os.environ["JAVA_CLASS"]
algorithms = parse_list("ALGORITHMS", str)
digit_ks = parse_list("DIGIT_KS", int)
duplicate_raw = os.environ.get("DUPLICATE_RATIOS", "")
if duplicate_raw.strip().upper() == "AUTO":
    duplicate_ratios = build_sequence(0.0, 1.0, 0.01, decimals=2)
else:
    duplicate_ratios = parse_list("DUPLICATE_RATIOS", float)

sorted_raw = os.environ.get("SORTED_RATIOS", "")
if sorted_raw.strip().upper() == "AUTO":
    sorted_ratios = build_sequence(0.0, 1.0, 0.01, decimals=2)
else:
    sorted_ratios = parse_list("SORTED_RATIOS", float)
size_experiment_arrays = parse_list("SIZE_EXPERIMENT_ARRAYS", int)
duplicate_tolerance = parse_float("DUPLICATE_TOLERANCE")
sorted_tolerance = parse_float("SORTED_TOLERANCE")
random_seed = parse_int("RANDOM_SEED")
runs_per_sample = parse_positive_int("RUNS_PER_SAMPLE")
warmup_runs = parse_nonnegative_int("WARMUP_RUNS")
run_digit_experiment = parse_bool("RUN_DIGIT_EXPERIMENT", True)
run_duplicate_experiment = parse_bool("RUN_DUPLICATE_EXPERIMENT", True)
run_sorted_experiment = parse_bool("RUN_SORTED_EXPERIMENT", True)
run_size_experiment = parse_bool("RUN_SIZE_EXPERIMENT", True)

if base_array_size <= 0:
    raise ValueError("ARRAY_SIZE must be > 0.")
if min_samples <= 0:
    raise ValueError("MIN_SAMPLES must be > 0.")
if max_samples < min_samples:
    raise ValueError("MAX_SAMPLES must be >= MIN_SAMPLES.")
if not algorithms:
    raise ValueError("ALGORITHMS must not be empty.")
if not digit_ks:
    raise ValueError("DIGIT_KS must not be empty.")
if not duplicate_ratios:
    raise ValueError("DUPLICATE_RATIOS must not be empty.")
if not sorted_ratios:
    raise ValueError("SORTED_RATIOS must not be empty.")
if run_size_experiment and not size_experiment_arrays:
    raise ValueError("SIZE_EXPERIMENT_ARRAYS must not be empty when RUN_SIZE_EXPERIMENT is enabled.")
if run_size_experiment:
    for val in size_experiment_arrays:
        if val <= 0:
            raise ValueError("SIZE_EXPERIMENT_ARRAYS values must be > 0.")

if not (0.5 <= confidence < 1.0):
    raise ValueError("Confidence must be in [0.5, 1.0).")

normal_dist = statistics.NormalDist(0.0, 1.0)
z_value = normal_dist.inv_cdf((1.0 + confidence) / 2.0)
SORT_TIMEOUT_SECONDS = 10
SORT_TIMEOUT_MS = SORT_TIMEOUT_SECONDS * 1000.0

class Stats:
    __slots__ = ("count", "mean", "m2")

    def __init__(self):
        self.count = 0
        self.mean = 0.0
        self.m2 = 0.0

    def add(self, value):
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        delta2 = value - self.mean
        self.m2 += delta * delta2

    def std(self):
        if self.count < 2:
            return float("nan")
        return math.sqrt(self.m2 / (self.count - 1))

    def half_width(self, z):
        std = self.std()
        if self.count < 1 or math.isnan(std):
            return float("nan")
        return z * std / math.sqrt(self.count)

    def power_ok(self, z, min_samples, max_half_width_ms, max_half_width_relative):
        if self.count < min_samples:
            return False
        half = self.half_width(z)
        if math.isnan(half):
            return False
        if half <= max_half_width_ms:
            return True
        if abs(self.mean) <= 1e-12:
            return False
        return (half / abs(self.mean)) <= max_half_width_relative

rng = random.Random(random_seed)

def max_digits(values):
    result = 0
    for v in values:
        x = v
        if x == -2**31:
            x = 2**31 - 1
        if x < 0:
            x = -x
        digits = 1
        while x >= 10:
            x //= 10
            digits += 1
        if digits > result:
            result = digits
    return result

def collision_ratio(values):
    counts = {}
    duplicates = 0
    for v in values:
        if v in counts:
            counts[v] += 1
            duplicates += 1
        else:
            counts[v] = 1
    return duplicates / len(values) if values else 0.0

def sorted_ratio(values):
    n = len(values)
    if n <= 1:
        return 1.0
    count = sum(1 for i in range(n - 1) if values[i] <= values[i + 1])
    return count / n

def generate_digits_sample(size, digits):
    max_bound = 10 ** digits - 1
    max_bound = min(max_bound, 2**31 - 1)
    if max_bound < 1:
        max_bound = 1
    values = [rng.randint(-max_bound, max_bound) for _ in range(size)]
    actual = max_digits(values)
    return {"values": values, "actual": actual}

def generate_duplicate_sample(size, target_ratio, tolerance, max_attempts=30):
    for _ in range(max_attempts):
        dup_target = round(target_ratio * size)
        dup_target = min(max(dup_target, 0), size - 1 if size > 0 else 0)
        unique_count = max(1, size - dup_target)

        unique_values = set()
        while len(unique_values) < unique_count:
            unique_values.add(rng.randint(-1_000_000, 1_000_000))
        unique_list = list(unique_values)

        values = unique_list[:unique_count]
        while len(values) < size:
            values.append(unique_list[rng.randrange(unique_count)])

        rng.shuffle(values)

        actual = collision_ratio(values)
        if abs(actual - target_ratio) <= tolerance:
            return {"values": values, "actual": actual}
    raise RuntimeError(f"Unable to generate duplicate sample for ratio {target_ratio} with tolerance {tolerance}.")

def generate_sorted_sample(size, target_ratio, tolerance, max_attempts=30):
    for _ in range(max_attempts):
        if size == 0:
            return {"values": [], "actual": 1.0}
        values = [0] * size
        values[0] = rng.randint(-500_000, 500_000)
        for i in range(size - 1):
            if rng.random() <= target_ratio:
                inc = rng.randint(0, 300)
                values[i + 1] = values[i] + inc
            else:
                dec = rng.randint(1, 300)
                values[i + 1] = values[i] - dec

        actual = sorted_ratio(values)
        if abs(actual - target_ratio) <= tolerance:
            return {"values": values, "actual": actual}
    raise RuntimeError(f"Unable to generate sortedness sample for ratio {target_ratio} with tolerance {tolerance}.")

def generate_uniform_sample(size):
    values = [rng.randint(-1_000_000, 1_000_000) for _ in range(size)]
    return {"values": values, "actual": float(size)}

def invoke_sorting_test(values, algorithm):
    input_lines = [str(len(values))]
    input_lines.extend(str(v) for v in values)
    input_lines.append(str(algorithm))
    input_lines.append("X")
    input_data = "\n".join(input_lines) + "\n"

    start = time.perf_counter()
    timed_out = False
    try:
        proc = subprocess.run(
            [java_command, java_class],
            input=input_data.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=script_dir,
            check=False,
            timeout=SORT_TIMEOUT_SECONDS,
        )
        elapsed_ms = (time.perf_counter() - start) * 1000.0
    except subprocess.TimeoutExpired:
        timed_out = True
        elapsed_ms = SORT_TIMEOUT_MS
        sys.stderr.write(
            f"[warn] Algorithm {algorithm} exceeded {SORT_TIMEOUT_SECONDS}s timeout; aborting run.\n"
        )
        return elapsed_ms, timed_out

    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode("utf-8", errors="ignore"))
        raise RuntimeError(f"{java_class} exited with code {proc.returncode}.")
    return elapsed_ms, timed_out

def perform_warmup():
    if warmup_runs <= 0:
        return
    warmup_size = max(512, min(base_array_size, 4096))
    base_values = [((i * 15485863) ^ 0x5DEECE66D) % 200000 - 100000 for i in range(warmup_size)]
    for algo in algorithms:
        for _ in range(warmup_runs):
            invoke_sorting_test(base_values, algo)

def has_full_power(states):
    return all(
        state.power_ok(z_value, min_samples, max_half_width_ms, max_half_width_relative)
        for state in states.values()
    )

def run_scenario(name, params, generator, raw_log):
    records = []
    for param in params:
        print(f"Running scenario '{name}' with parameter {param}...")
        states = {algo: Stats() for algo in algorithms}
        actuals = {algo: Stats() for algo in algorithms}
        power_satisfied = False

        for rep in range(1, max_samples + 1):
            sample = generator(param)
            values = sample["values"]
            actual = sample["actual"]

            for algo in algorithms:
                times = []
                for run_index in range(1, runs_per_sample + 1):
                    elapsed, timed_out = invoke_sorting_test(values, algo)
                    times.append(elapsed)
                    raw_log.append(
                        {
                            "Scenario": name,
                            "Parameter": param,
                            "ActualParameter": actual,
                            "Replicate": rep,
                            "RunIndex": run_index,
                            "Algorithm": algo,
                            "ElapsedMs": round(elapsed, 6),
                            "TimedOut": timed_out,
                        }
                    )
                    if timed_out:
                        break

                mean_elapsed = sum(times) / len(times)
                states[algo].add(mean_elapsed)
                actuals[algo].add(actual)

            if has_full_power(states):
                print(f"  Achieved target power after {rep} replicates.")
                power_satisfied = True
                break

        if not power_satisfied:
            print(
                f"WARNING: Scenario '{name}' parameter {param} reached max samples without hitting all confidence targets.",
                file=sys.stderr,
            )

        for algo in algorithms:
            state = states[algo]
            std = state.std()
            half = state.half_width(z_value)
            records.append(
                {
                    "Scenario": name,
                    "Parameter": param,
                    "Algorithm": algo,
                    "Samples": state.count,
                    "MeanMs": round(state.mean, 6) if not math.isnan(state.mean) else float("nan"),
                    "StdMs": round(std, 6) if not math.isnan(std) else float("nan"),
                    "HalfWidthMs": round(half, 6) if not math.isnan(half) else float("nan"),
                    "PowerSatisfied": state.power_ok(z_value, min_samples, max_half_width_ms, max_half_width_relative),
                    "ActualParameterMean": round(actuals[algo].mean, 6)
                    if not math.isnan(actuals[algo].mean)
                    else float("nan"),
                }
            )
    return records

def compute_recommendations(records):
    recommendations = {}

    def best_by_parameter(subset):
        groups = defaultdict(list)
        for row in subset:
            groups[row["Parameter"]].append(row)
        best_rows = []
        for param, rows in groups.items():
            best = min(rows, key=lambda r: r["MeanMs"])
            best_rows.append(
                {
                    "Parameter": param,
                    "Algorithm": best["Algorithm"],
                    "MeanMs": best["MeanMs"],
                }
            )
        best_rows.sort(key=lambda r: r["Parameter"])
        return best_rows

    digits_records = [r for r in records if r["Scenario"] == "digits"]
    if digits_records:
        digits_summary = best_by_parameter(digits_records)
        radix_rows = [row for row in digits_summary if row["Algorithm"] == "R"]
        if radix_rows:
            recommendations["k_digits"] = radix_rows[-1]["Parameter"]
        else:
            recommendations["k_digits"] = digit_ks[0] - 1 if digit_ks else 0
        recommendations["digits_summary"] = digits_summary

    dup_records = [r for r in records if r["Scenario"] == "duplicates"]
    if dup_records:
        dup_summary = best_by_parameter(dup_records)
        insertion_rows = [row for row in dup_summary if row["Algorithm"] == "I"]
        if insertion_rows:
            recommendations["k_collision"] = insertion_rows[0]["Parameter"]
        else:
            recommendations["k_collision"] = 1.1
        recommendations["duplicates_summary"] = dup_summary

    sorted_records = [r for r in records if r["Scenario"] == "sortedness"]
    if sorted_records:
        sorted_summary = best_by_parameter(sorted_records)
        insertion_rows = [row for row in sorted_summary if row["Algorithm"] == "I"]
        if insertion_rows:
            recommendations["k_sorted"] = insertion_rows[0]["Parameter"]
        else:
            recommendations["k_sorted"] = 1.1
        recommendations["sorted_summary"] = sorted_summary

    recommendations["default_algorithm"] = "Q"
    return recommendations

def write_summary(recommendations, path):
    lines = []
    lines.append("Experiment Summary")
    lines.append("-------------------")

    if "k_digits" in recommendations:
        lines.append(f"Digits experiment: recommend radix sort when max digits <= {recommendations['k_digits']}.")
        lines.append("Per-digit winners:")
        for row in recommendations.get("digits_summary", []):
            lines.append(f"  k={row['Parameter']}: {row['Algorithm']} ({row['MeanMs']} ms)")
        lines.append("")

    if "k_collision" in recommendations:
        if recommendations["k_collision"] > 1.0:
            lines.append("Duplicates experiment: insertion sort never dominated in tested range.")
        else:
            lines.append(
                "Duplicates experiment: recommend insertion sort when collision ratio >= "
                f"{recommendations['k_collision']:.2f}."
            )
        lines.append("Per-ratio winners:")
        for row in recommendations.get("duplicates_summary", []):
            lines.append(f"  ratio={row['Parameter']:.2f}: {row['Algorithm']} ({row['MeanMs']} ms)")
        lines.append("")

    if "k_sorted" in recommendations:
        if recommendations["k_sorted"] > 1.0:
            lines.append("Sortedness experiment: insertion sort never dominated in tested range.")
        else:
            lines.append(
                "Sortedness experiment: recommend insertion sort when sorted ratio >= "
                f"{recommendations['k_sorted']:.2f}."
            )
        lines.append("Per-ratio winners:")
        for row in recommendations.get("sorted_summary", []):
            lines.append(f"  ratio={row['Parameter']:.2f}: {row['Algorithm']} ({row['MeanMs']} ms)")
        lines.append("")

    lines.append(f"Default fallback algorithm: {recommendations.get('default_algorithm', 'Q')}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

output_dir = script_dir / "experiment_results"
output_dir.mkdir(exist_ok=True)

perform_warmup()

raw_measurements = []
records = []
scenario_plan = []

if run_digit_experiment:
    scenario_plan.append(
        (
            "digits",
            digit_ks,
            lambda param: generate_digits_sample(base_array_size, param),
        )
    )

if run_duplicate_experiment:
    scenario_plan.append(
        (
            "duplicates",
            duplicate_ratios,
            lambda param: generate_duplicate_sample(base_array_size, param, duplicate_tolerance),
        )
    )

if run_sorted_experiment:
    scenario_plan.append(
        (
            "sortedness",
            sorted_ratios,
            lambda param: generate_sorted_sample(base_array_size, param, sorted_tolerance),
        )
    )

if run_size_experiment:
    scenario_plan.append(
        (
            "array_size",
            size_experiment_arrays,
            lambda param: generate_uniform_sample(int(param)),
        )
    )

for name, params, generator in scenario_plan:
    records.extend(run_scenario(name, params, generator, raw_measurements))

stats_path = output_dir / "experiment_statistics.csv"
fieldnames = [
    "Scenario",
    "Parameter",
    "Algorithm",
    "Samples",
    "MeanMs",
    "StdMs",
    "HalfWidthMs",
    "PowerSatisfied",
    "ActualParameterMean",
]
with stats_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row in records:
        writer.writerow(row)

raw_path = output_dir / "execution_times.csv"
raw_fieldnames = [
    "Scenario",
    "Parameter",
    "ActualParameter",
    "Replicate",
    "RunIndex",
    "Algorithm",
    "ElapsedMs",
    "TimedOut",
]
with raw_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=raw_fieldnames)
    writer.writeheader()
    for row in raw_measurements:
        writer.writerow(row)

recommendations = compute_recommendations(records)
summary_path = output_dir / "analysis_summary.txt"
write_summary(recommendations, summary_path)

config_path = output_dir / "search_config.json"
with config_path.open("w", encoding="utf-8") as f:
    json.dump(recommendations, f, indent=2)

print("Experiment data saved to:")
print(f"  Statistics: {stats_path}")
print(f"  Execution:  {raw_path}")
print(f"  Summary:    {summary_path}")
print(f"  Config:     {config_path}")
PY
