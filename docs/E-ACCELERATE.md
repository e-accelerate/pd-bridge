# e-accelerate contributions

This is a fork of [Chad Hurley's pd-bridge](https://github.com/chadhurley25075-png/pd-bridge),
under Apache-2.0. The bridge idea, original implementation, and original measurements remain
attributed to upstream. See LICENSE and NOTICE for the original terms and credits.

## Benchmark runner reliability (2026-09-07)

Previously, `make bench-quick` piped a loop to `tee results/...` without creating `results/`.
A new checkout could lose its output; a failed client request could be hidden by a successful
`tee`. Fixed seeds were also reused between sizes and subsequent invocations.

The fork adds `scripts/bench-quick.sh` and makes the existing target call it:

- Creates the output directory and uses a unique filename to avoid overwriting results.
- Stops at the first failed client request and reports pipeline/write failures as failures.
- Retains partial JSONL results for diagnosis; announces the output path before requests begin.
- Uses a different seed per request, starting from the current Unix second by default.
- Preserves all client output, including upstream's bridge verdict and needle-retrieval result.
  Successful execution alone does not establish a complete bridge or correct output.

Configure and source `config.env` as described in the upstream README, then run:

```bash
make bench-quick
# Optional reproducible starting seed and output directory:
BENCH_SEED=12001 BENCH_RESULTS_DIR=results make bench-quick
make test-runner
```

`FRONT` and `NATIVE` select the two endpoints. `PY_BENCH` selects the Python interpreter
(default `python3`). Each run executes 18 requests: three repetitions of three prompt sizes
on each endpoint. Output filenames start with `bench-quick-`; their contents are JSONL.
Do not reuse a seed range against an already warmed cache when claiming cold results.
Default runs started in the same second also share seeds; choose separate ranges in that case.
Different synthetic documents are not proof of zero cache overlap: inspect the verdicts.

Regression tests use a fake client to check the matrix, distinct seeds, saved output,
client failure propagation, partial-result retention, unique files, invalid configuration,
and output failures. They require only Python's standard library and Bash.

No new inference speedups, model ports, or hardware validation are claimed by this change.
The original pooling selftest additionally requires PyTorch; full-fabric benchmarking
requires the configured NVIDIA and Apple Silicon inference servers.
