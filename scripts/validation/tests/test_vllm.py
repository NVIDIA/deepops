"""Offline HTTP fixtures: never start vLLM, download weights, or use a GPU."""
import contextlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "validate_vllm.py"
REVISION = "a" * 40


@contextlib.contextmanager
def endpoint(responses):
    requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.respond()

        def do_POST(self):
            self.respond()

        def respond(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            requests.append((self.command, self.path, json.loads(body) if body else None))
            status, value, headers, delay = responses[self.path]
            time.sleep(delay)
            data = value if isinstance(value, bytes) else json.dumps(value).encode()
            self.send_response(status)
            for key, value in headers.items():
                self.send_header(key, value)
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01})
    thread.start()
    try:
        yield "http://127.0.0.1:" + str(server.server_port), requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class VllmTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cache = Path(self.tmp.name)
        self.snapshot = self.cache / "models--example--model" / "snapshots" / REVISION
        self.snapshot.mkdir(parents=True)
        for name in ("config.json", "tokenizer.json", "model.safetensors"):
            (self.snapshot / name).write_text("fixture only")
        self.responses = {
            "/health": (200, b"", {}, 0),
            "/v1/models": (200, {"object": "list", "data": [{"id": "test-model", "object": "model"}]}, {}, 0),
            "/v1/completions": (200, {
                "id": "cmpl-test", "object": "text_completion", "model": "test-model",
                "choices": [{"index": 0, "text": "generated fixture", "finish_reason": "length"}],
                "usage": {"prompt_tokens": 5, "completion_tokens": 8, "total_tokens": 13},
            }, {}, 0),
        }

    def run_validator(self, url, *extra, env=None):
        args = [sys.executable, str(SCRIPT), "--json", "--base-url", url,
                "--model", "test-model", "--cache-dir", str(self.cache),
                "--repo-id", "example/model", "--revision", REVISION]
        for name in ("config.json", "tokenizer.json", "model.safetensors"):
            args += ["--require-file", name]
        run = subprocess.run(args + list(extra), capture_output=True, text=True,
                             timeout=5, env=env)
        self.assertEqual(run.stderr, "", run.stderr)
        self.assertIn(run.returncode, (0, 1), run.stderr)
        result = json.loads(run.stdout)
        self.assertEqual(result["schema_version"], 1)
        self.assertEqual(result["ok"], run.returncode == 0)
        return result

    def test_success_requires_cache_health_model_and_completion(self):
        with endpoint(self.responses) as (url, requests):
            result = self.run_validator(url)
        self.assertTrue(result["ok"])
        self.assertEqual(result["checks"], {"cache": True, "health": True,
                                            "model": True, "completion": True})
        self.assertEqual(result["errors"], [])
        self.assertEqual([(r[0], r[1]) for r in requests], [
            ("GET", "/health"), ("GET", "/v1/models"), ("POST", "/v1/completions")])
        self.assertEqual(requests[-1][2], {"model": "test-model", "prompt": "The capital of France is",
                                          "max_tokens": 8, "temperature": 0, "stream": False})
        self.assertNotIn("generated fixture", json.dumps(result))

    def test_missing_cache_file_prevents_all_http(self):
        (self.snapshot / "model.safetensors").unlink()
        with endpoint(self.responses) as (url, requests):
            result = self.run_validator(url)
        self.assertFalse(result["ok"])
        self.assertEqual(result["errors"][0]["stage"], "cache")
        self.assertEqual(requests, [])

    def test_mutable_revision_prevents_all_http(self):
        with endpoint(self.responses) as (url, requests):
            result = self.run_validator(url, "--revision", "main")
        self.assertFalse(result["ok"])
        self.assertEqual(requests, [])

    def test_health_failure_stops_before_inference(self):
        self.responses["/health"] = (503, b"private server details", {}, 0)
        with endpoint(self.responses) as (url, requests):
            result = self.run_validator(url)
        self.assertFalse(result["ok"])
        self.assertEqual(result["errors"][0]["stage"], "health")
        self.assertEqual(len(requests), 1)
        self.assertNotIn("private server details", json.dumps(result))

    def test_model_must_be_advertised_and_models_shape_valid(self):
        for value in ({"data": [{"id": "other"}]}, {"data": []}, [], None,
                      {"data": "test-model"}, {"data": [None]}, b"not json"):
            with self.subTest(value=value):
                self.responses["/v1/models"] = (200, value, {}, 0)
                with endpoint(self.responses) as (url, requests):
                    result = self.run_validator(url)
                self.assertFalse(result["ok"])
                self.assertEqual(result["errors"][0]["stage"], "model")
                self.assertEqual(len(requests), 2)

    def test_completion_must_prove_nonempty_output_for_expected_model(self):
        good = self.responses["/v1/completions"][1]
        bad = [None, [], {}, {**good, "model": "other"}, {**good, "choices": []},
               {**good, "choices": [None]}, {**good, "choices": [{"text": " "}]},
               {**good, "choices": [{"text": 7}]},
               {**good, "usage": {"completion_tokens": 0}},
               {**good, "usage": {"completion_tokens": True}},
               {**good, "usage": None}, b"broken json"]
        for value in bad:
            with self.subTest(value=value):
                self.responses["/v1/completions"] = (200, value, {}, 0)
                with endpoint(self.responses) as (url, _):
                    result = self.run_validator(url)
                self.assertFalse(result["ok"])
                self.assertEqual(result["errors"][0]["stage"], "completion")

    def test_redirect_never_followed(self):
        with endpoint(self.responses) as (destination, redirected):
            self.responses["/health"] = (302, b"", {"Location": destination + "/health"}, 0)
            with endpoint(self.responses) as (url, _):
                result = self.run_validator(url)
        self.assertFalse(result["ok"])
        self.assertEqual(redirected, [])

    def test_proxies_are_ignored(self):
        with endpoint(self.responses) as (proxy, proxied):
            env = {**os.environ, "http_proxy": proxy, "HTTP_PROXY": proxy,
                   "https_proxy": proxy, "HTTPS_PROXY": proxy, "ALL_PROXY": proxy,
                   "no_proxy": "", "NO_PROXY": ""}
            with endpoint(self.responses) as (url, _):
                result = self.run_validator(url, env=env)
        self.assertTrue(result["ok"])
        self.assertEqual(proxied, [])

    def test_only_bare_loopback_http_origins_accepted(self):
        for url in ("http://example.com:8000", "https://127.0.0.1:8000", "file:///etc/passwd",
                    "http://user:example@127.0.0.1:8000", "http://127.0.0.1:8000/path",
                    "http://127.0.0.1:8000/?x=1", "http://127.0.0.1:8000/#fragment",
                    "http://localhost:8000", "http://127.0.0.1:99999"):
            with self.subTest(url=url):
                result = self.run_validator(url)
                self.assertFalse(result["ok"])
                self.assertEqual(result["errors"][0]["stage"], "arguments")
                self.assertNotIn("user:example", json.dumps(result))

    def test_timeout_is_bounded_and_machine_readable(self):
        self.responses["/health"] = (200, b"", {}, 0.2)
        with endpoint(self.responses) as (url, requests):
            result = self.run_validator(url, "--timeout", "0.05")
        self.assertFalse(result["ok"])
        self.assertEqual(result["errors"][0]["stage"], "health")
        self.assertEqual(len(requests), 1)

    def test_invalid_timeouts_rejected_before_http(self):
        for timeout in ("0", "-1", "nan", "inf", "121"):
            with self.subTest(timeout=timeout):
                with endpoint(self.responses) as (url, requests):
                    result = self.run_validator(url, "--timeout", timeout)
                self.assertFalse(result["ok"])
                self.assertEqual(requests, [])

    def test_oversized_response_rejected(self):
        self.responses["/v1/models"] = (200, b" " * (1024 * 1024 + 1), {}, 0)
        with endpoint(self.responses) as (url, _):
            result = self.run_validator(url)
        self.assertFalse(result["ok"])
        self.assertEqual(result["errors"][0]["stage"], "model")

    def test_connection_refused_is_json_failure(self):
        with endpoint(self.responses) as (url, _):
            pass
        result = self.run_validator(url)
        self.assertFalse(result["ok"])
        self.assertEqual(result["errors"][0]["stage"], "health")

    def test_unknown_cli_flag_is_usage_error(self):
        run = subprocess.run([sys.executable, str(SCRIPT), "--unknown"],
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn("usage:", run.stderr)


if __name__ == "__main__":
    unittest.main()
