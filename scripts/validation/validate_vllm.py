#!/usr/bin/env python3
"""Check a local vLLM server with one small inference request; never launch it."""
import argparse
import http.client
import ipaddress
import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from validate_model_cache import validate as validate_cache


class ValidationError(Exception):
    """A failed readiness check, safe to report without server response data."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValidationError("HTTP redirects are not allowed")


def local_origin(value):
    try:
        parsed = urllib.parse.urlsplit(value)
        if (parsed.scheme != "http" or not parsed.hostname
                or not ipaddress.ip_address(parsed.hostname).is_loopback
                or "@" in parsed.netloc
                or parsed.path not in ("", "/") or parsed.query or parsed.fragment
                or parsed.port is None or not 1 <= parsed.port <= 65535):
            raise ValueError
        return "http://" + parsed.netloc
    except ValueError:
        raise ValidationError("base URL must be an HTTP loopback IP with an explicit port and no credentials, path, query, or fragment") from None


def request(opener, origin, path, timeout, payload=None, expect_json=True):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(origin + path, data=data,
                                 headers={"Content-Type": "application/json", "Accept": "application/json"})
    try:
        deadline = time.monotonic() + timeout
        with opener.open(req, timeout=timeout) as response:
            if response.status != 200:
                raise ValidationError("endpoint did not return HTTP 200")
            # Bound memory and check elapsed time between socket reads, including
            # peers that drip bytes without triggering a socket inactivity timeout.
            body = bytearray()
            while True:
                if time.monotonic() >= deadline:
                    raise ValidationError("endpoint response exceeded the time limit")
                chunk = response.read1(min(65536, 1024 * 1024 + 1 - len(body)))
                body.extend(chunk)
                if len(body) > 1024 * 1024:
                    raise ValidationError("endpoint response exceeds 1 MiB")
                if not chunk:
                    break
        return json.loads(body) if expect_json else None
    except urllib.error.HTTPError as exc:
        status = exc.code
        exc.close()
        raise ValidationError("endpoint returned HTTP " + str(status)) from None
    except (OSError, urllib.error.URLError, http.client.HTTPException):
        raise ValidationError("endpoint unreachable, timed out, or connection failed") from None
    except (ValueError, UnicodeError, RecursionError):
        raise ValidationError("endpoint returned invalid JSON") from None


def validate(args):
    result = {
        "schema_version": 1,
        "ok": False,
        "checks": {"cache": False, "health": False, "model": False, "completion": False},
        "cache": None,
        "errors": [],
    }
    stage = "arguments"
    try:
        origin = local_origin(args.base_url)
        if not math.isfinite(args.timeout) or not 0 < args.timeout <= 120:
            raise ValidationError("timeout must be greater than zero and at most 120 seconds")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}", args.model):
            raise ValidationError("model must be a nonempty served model name (maximum 256 characters)")
        stage = "cache"
        result["cache"] = validate_cache(args.cache_dir, args.repo_id, args.revision, args.require_file)
        if not result["cache"]["ok"]:
            raise ValidationError("required pinned cache files failed validation; see cache.errors")
        result["checks"][stage] = True
        # Never inherit proxy routing or forward a local request via a redirect.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        stage = "health"
        request(opener, origin, "/health", args.timeout, expect_json=False)
        result["checks"][stage] = True
        stage = "model"
        models = request(opener, origin, "/v1/models", args.timeout)
        if (not isinstance(models, dict) or not isinstance(models.get("data"), list)
                or not all(isinstance(item, dict) for item in models["data"])
                or not any(item.get("id") == args.model for item in models["data"])):
            raise ValidationError("expected served model is absent or model-list response is malformed")
        result["checks"][stage] = True
        stage = "completion"
        completion = request(opener, origin, "/v1/completions", args.timeout, {
            "model": args.model, "prompt": "The capital of France is",
            "max_tokens": 8, "temperature": 0, "stream": False,
        })
        if not isinstance(completion, dict) or completion.get("model") != args.model:
            raise ValidationError("completion response does not identify the expected model")
        choices = completion.get("choices")
        usage = completion.get("usage")
        if (not isinstance(choices, list) or not choices or not isinstance(choices[0], dict)
                or not isinstance(choices[0].get("text"), str) or not choices[0]["text"].strip()
                or not isinstance(usage, dict) or type(usage.get("completion_tokens")) is not int
                or not 0 < usage["completion_tokens"] <= 8):
            raise ValidationError("completion must contain nonempty text and 1 to 8 generated tokens")
        result["checks"][stage] = True
        result["ok"] = True
    except ValidationError as exc:
        result["errors"].append({"stage": stage, "message": str(exc)})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000",
                        help="Loopback HTTP origin, without /v1; proxies and redirects disabled")
    parser.add_argument("--model", required=True, help="Expected --served-model-name")
    parser.add_argument("--cache-dir", required=True, help="Explicit shared HF_HUB_CACHE")
    parser.add_argument("--repo-id", required=True)
    parser.add_argument("--revision", required=True, help="Full immutable model commit hash")
    parser.add_argument("--require-file", required=True, action="append",
                        help="Required snapshot file; repeat for all configuration, tokenizer and weight files")
    parser.add_argument("--timeout", type=float, default=30, help="Socket timeout and response-body time budget, 0 < seconds <= 120")
    parser.add_argument("--json", action="store_true", help="Emit schema-versioned JSON without generated text")
    args = parser.parse_args()
    result = validate(args)
    if args.json:
        print(json.dumps(result, sort_keys=True))
    elif result["ok"]:
        print("PASS: cache, health, model and completion checks passed")
    else:
        print("FAIL: " + "; ".join(error["stage"] + ": " + error["message"] for error in result["errors"]))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
