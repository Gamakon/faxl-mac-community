# faxl — Tester Instructions (time-limited build)

Thanks for testing faxl. This is a **12-month tester build**: it needs **no
licence and no key**, runs fully offline, and simply stops accelerating after
its built-in expiry (the proxy keeps working, just without the speed-up).

faxl is a caching proxy for local LLMs on Apple silicon. When a prompt shares
a prefix with one it has seen, it skips re-processing that prefix — repeated
and multi-turn prompts get their first token back far faster, with
**byte-identical** output.

## What you need
- A Mac with Apple silicon (M1–M4).
- **Python 3.12** (`brew install python@3.12` if missing).
- ~40 GB free disk (one-time model download).
- The two wheels shipped with this file: `faxl-…-arm64.whl` and
  `UltraDim-…-cp312-…-arm64.whl`.

## Install & run (copy-paste)

```bash
python3.12 -m venv faxl-env && source faxl-env/bin/activate
pip install ./faxl-0.1.0-cp39-abi3-macosx_11_0_arm64.whl ./UltraDim-0.3.7-cp312-cp312-macosx_11_0_arm64.whl mlx mlx-lm

# persistent cache dirs so warmed state survives restarts
export FAXL_BLOBS="$HOME/faxl-cache/blobs" FAXL_DB="$HOME/faxl-cache/db"
faxl-proxy
```

That's it — the engine ships inside the wheel. First run downloads the default
model (`mlx-community/granite-4.0-h-small-8bit`, ~34 GB) once. Different MLX
model: `export FAXL_MODEL=<mlx-community/repo>` first.

## Use it
Point **any** OpenAI-compatible client at `http://127.0.0.1:8080/v1` (any api
key value; it's ignored). Send a request, then a **follow-up that extends the
same conversation** — the shared prefix is served from cache; you'll see a
`warm(...)` line in the proxy output and a much faster first token.

**Watch it work:** open `http://127.0.0.1:8080/console` — tokens skipped, time
saved, warm vs cold latency.

## What to report
- First-token latency: cold request vs a follow-up in the same conversation.
- Correctness: cached answers must be identical to uncached
  (`export FAXL_NOCACHE=1` + restart = same proxy with the cache off, for A/B).
- Your real workload: point your agent/app at the proxy and note the
  % of prompt tokens skipped (shown in the console).
- Anything that breaks or looks wrong: **andrew@gamakon.ai**

## Notes
- Offline: nothing phones home; no licence server; prompts never leave your Mac.
- The cache stores model state and hashes, not readable prompt text.
- This build stops accelerating ~12 months after it was built; ask for a fresh
  build (faxl.ai) if you need longer.
