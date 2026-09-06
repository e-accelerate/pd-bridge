SHELL := /bin/bash
-include hetero.env
export
PY_SPARK ?= python3          # inside the vllm container: /opt/env/bin/python
PY_MAC   ?= python3          # the oMLX venv python (e.g. ~/omlx064/bin/python)
FRONT    ?= http://127.0.0.1:8012
NATIVE   ?= http://127.0.0.1:8011

.PHONY: help doctor test test-mac test-spark weights demo bench-quick scrub-check test-runner

help:
	@echo "make doctor      — check every link in the chain (run this first, always)"
	@echo "make test        — CPU-only tests, run anywhere (CI tier): hook selftest + scrub check"
	@echo "make test-mac    — Mac-side tests (needs the oMLX venv + model; synthetic writer vs reference block)"
	@echo "make test-spark  — in-container smoke test (needs the running vllm_pd container + weights)"
	@echo "make weights     — regenerate dv4_proj_weights.safetensors from YOUR MLX model (never downloaded)"
	@echo "make demo        — one cold bridged request + its warm rerun + the native A/B (fixed seed)"
	@echo "make bench-quick — cold 20K/80K/100K bridged vs native, fresh seeds, verdicts recorded"
	@echo "make scrub-check — fail on any personal path/address in tracked files"

doctor: ; @bash scripts/hetero-doctor.sh

test-runner:
	python3 -m unittest discover -s tests -v

test: test-runner
	$(PY_SPARK) spark/pd_pool_selftest.py --T 5000
	bash scripts/scrub-check.sh

test-mac:
	$(PY_MAC) studio/test_block_writer_synthetic.py --ref "$$(find $$HOME/.omlx/cache -name '*.safetensors' | head -1)" --out /tmp/pd_blocks_test
	$(PY_MAC) /tmp/test_stream_path.py 2>/dev/null || echo "(streaming-path test: see studio/omlx_block_writer.py begin_stream/store_boundary; covered by bench-quick at 100K)"

test-spark:
	docker exec vllm_pd /opt/env/bin/python /pd_v3/pd_pool_selftest.py --smoke --weights /pd_v3/dv4_proj_weights.safetensors

weights:
	$(PY_MAC) studio/pd_export_proj_weights.py --model "$(PD_MODEL)" --out "$(PD_V3_DIR)"

demo:
	@echo "== cold leg (bridge):";       python3 bench/bench_cold.py --chars 75000 --seed 901 --url $(FRONT)
	@echo "== warm leg (front steps aside):"; python3 bench/bench_cold.py --chars 75000 --seed 901 --url $(FRONT)
	@echo "== native A/B (fresh seed):";  python3 bench/bench_cold.py --chars 75000 --seed 902 --url $(NATIVE)
	@echo "Each line's \"bridge\" field is the front door's own verdict — read it, don't trust the label."

bench-quick:
	bash scripts/bench-quick.sh

scrub-check: ; @bash scripts/scrub-check.sh
