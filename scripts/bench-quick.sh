#!/usr/bin/env bash
# e-accelerate contribution: retain results and propagate benchmark failures.
set -euo pipefail
cd "$(dirname "$0")/.."

front="${FRONT:-http://127.0.0.1:8012}"
native="${NATIVE:-http://127.0.0.1:8011}"
python="${PY_BENCH:-python3}"
results_dir="${BENCH_RESULTS_DIR:-results}"
seed="${BENCH_SEED:-$(date +%s)}"
if [[ ! "$seed" =~ ^[0-9]{1,10}$ ]]; then
    echo "BENCH_SEED must be an unsigned integer of at most 10 digits" >&2
    exit 2
fi
seed=$((10#$seed))
mkdir -p "$results_dir"
result_file=$(mktemp "$results_dir/bench-quick-$(date +%Y%m%d-%H%M%S)-XXXXXX")
echo "Benchmark JSONL: $result_file" >&2
# Keep partial results when a request fails. pipefail also catches write errors.
# A distinct seed for every request avoids shared document prefixes across sizes.
{
    for repeat in 1 2 3; do
        for endpoint in "$front" "$native"; do
            for chars in 75000 330000 410000; do
                "$python" bench/bench_cold.py --chars "$chars" --seed "$seed" --url "$endpoint"
                seed=$((seed + 1))
            done
        done
    done
} | tee "$result_file"
echo "Completed 18 requests. Check each bridge verdict and found field before comparing times." >&2
echo "Missing, partial, skipped, or bridge_error verdicts are not complete bridged results." >&2
