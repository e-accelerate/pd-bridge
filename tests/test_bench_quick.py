"""Exercise the real shell runner with a fake benchmark client; no model needed."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BenchmarkRunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.client = self.directory / "fake-python"
        self.client.write_text("""#!/usr/bin/env python3
import json, os, sys
args = dict(zip(sys.argv[2::2], sys.argv[3::2]))
if args['--seed'] == os.environ.get('FAIL_SEED'):
    sys.exit(7)
print(json.dumps(args))
""")
        self.client.chmod(0o755)
        self.env = dict(os.environ, PY_BENCH=str(self.client),
                        BENCH_RESULTS_DIR=str(self.directory / "results"),
                        BENCH_SEED="100", FRONT="http://bridge.example:8012",
                        NATIVE="http://native.example:8011")
        self.env.pop("FAIL_SEED", None)

    def run_runner(self):
        return subprocess.run(["bash", "scripts/bench-quick.sh"], cwd=ROOT,
                              env=self.env, text=True, capture_output=True)

    def results(self):
        return list((self.directory / "results").glob("bench-quick-*"))

    def test_matrix_and_persisted_jsonl(self):
        result = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(rows), 18)
        self.assertEqual([int(row["--seed"]) for row in rows], list(range(100, 118)))
        for url in (self.env["FRONT"], self.env["NATIVE"]):
            for chars in ("75000", "330000", "410000"):
                self.assertEqual(sum(row["--url"] == url and row["--chars"] == chars
                                     for row in rows), 3)
        self.assertEqual(self.results()[0].read_text(), result.stdout)

    def test_failure_stops_matrix_and_preserves_partial_results(self):
        self.env["FAIL_SEED"] = "102"
        result = self.run_runner()
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 2)
        self.assertEqual(self.results()[0].read_text(), result.stdout)
        self.assertNotIn("Completed 18", result.stderr)

    def test_repeated_run_does_not_overwrite(self):
        self.assertEqual(self.run_runner().returncode, 0)
        self.assertEqual(self.run_runner().returncode, 0)
        self.assertEqual(len(self.results()), 2)

    def test_invalid_seed_fails_before_requests(self):
        self.env["BENCH_SEED"] = "bad"
        result = self.run_runner()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.results())

    def test_output_directory_failure_stops_before_requests(self):
        blocked = self.directory / "blocked"
        blocked.write_text("file, not directory")
        self.env["BENCH_RESULTS_DIR"] = str(blocked)
        result = self.run_runner()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_tee_failure_is_not_success(self):
        fake_tee = self.directory / "tee"
        fake_tee.write_text("#!/bin/sh\ncat >/dev/null\nexit 9\n")
        fake_tee.chmod(0o755)
        self.env["PATH"] = str(self.directory) + os.pathsep + os.environ["PATH"]
        result = self.run_runner()
        self.assertEqual(result.returncode, 9, result.stderr)
        self.assertNotIn("Completed 18", result.stderr)
