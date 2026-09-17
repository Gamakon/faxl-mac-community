# faxl — Mac community releases

**faxl** (faxl.ai, Gamakon Ltd) is a caching proxy for local LLM inference on
Apple silicon. It saves the model's working state to disk, and when a new
request begins with a prompt prefix the model has already processed, it
verifies the match byte-for-byte and skips that prefix. The model computes only
the new tokens.

Output is byte-identical to running without the cache. The whole engine ships
inside the wheel: install it, run `faxl-proxy`, point any OpenAI-compatible
client at it.

This repo carries the **released wheels** for the Mac community edition.
Source lives in the private faxl repos; this is a release target.

## What it does

**Skips prompt processing you have already paid for.** A growing conversation,
a fixed system prompt, a RAG preamble, an agent loop — anything that resends a
shared prefix. Second and later turns return their first token far faster. A
reference run cut paid prompt processing 62% over five turns. Generation speed
is untouched by any cache, so the saving is in time-to-first-token, not tokens
per second.

**Serves hybrid and recurrent models correctly, which is the hard part.**
Mamba, SSM and linear-attention models — Qwen3.5, Kimi Linear, Granite 4.0-h,
Nemotron-H, Ling — keep one rolled-up recurrent tensor instead of a KV cache.
Cached without handling that, they return a *plausible wrong answer* and
nothing tells you it happened. faxl detects the cache family at boot and
replays the real state. It also carries model loaders `mlx_lm` does not ship,
so some of these models run through faxl that otherwise would not run at all.

**Proves it is lossless, on demand.** `/console/verify` runs cache-on against
cache-off and reports byte-identity. `FAXL_NOCACHE=1` gives you the same proxy
with the cache off for your own A/B.

**A web console** at `/console`: tokens skipped, time saved, warm vs cold
latency, cache contents, a live request feed with per-request detail, and the
verify check. Served by the proxy itself, no external assets, works offline.
Renders for browsers, and as plain text or JSON for terminals and agents.

**An MCP server** (`faxl-mcp`, installed alongside) exposing start, stop,
status, licence and metrics as typed tools, so an agent can operate the proxy
without shelling out. Registered automatically by the included `.mcp.json`.

**A persistent, managed store.** State survives restarts and warm-starts on
boot. Checkpoints are keyed and verified under a namespace of model plus
config, so several models share one store and can never serve each other's
state. Scored eviction under a size cap you set, durable usage counters, and
an audit trail.

**Offline by design.** No licence server, no phone-home, nothing leaves the
machine. Licence keys are Ed25519-signed and verified locally against a public
key compiled into the wheel.

### Not in this build

Vision and image caching, the model register page, and the console's power
controls are on the development line and are not in the published wheel.

## Install

See [faxl_tester_instructions.md](faxl_tester_instructions.md). Short version:
Python 3.12, `pip install` the two wheels + `mlx mlx-lm`, run `faxl-proxy`.

**AI agents:** read [AGENTS.md](AGENTS.md) — full operating instructions,
plus an MCP server (`faxl-mcp`, installed with the wheel; registered by the
included [.mcp.json](.mcp.json)) exposing start/stop/status/licence/metrics
as typed tools.

## Shared server

Running one Mac (e.g. a lab Mac Studio) as a long-lived proxy for several
people is supported. Note the proxy has **no authentication** and binds to
loopback by default; the tester guide's
[shared server section](faxl_tester_instructions.md#running-it-as-a-shared-server-eg-a-lab-mac-studio)
covers exposure, concurrency, storage caps, Qwen settings and a launchd
service definition.

## Release notes

[CHANGELOG.md](CHANGELOG.md) — what changed in each wheel and whether you need
to re-download. The filename does not change between releases; check
`EXPIRY_EPOCH.txt` or `/health` to see which build you have.

## Current release

- `faxl-0.1.0-…-arm64.whl` — **time-limited tester build** (no licence key
  needed; stops accelerating ~12 months after build; the proxy itself keeps
  working). Expiry (unix epoch) in `EXPIRY_EPOCH.txt`.
- `UltraDim-0.3.7-…-cp312-….whl` — the index wheel (Python 3.12).

Licensed builds (named 1-year keys from faxl.ai) replace the tester build at
launch; monthly wheel refreshes carry a 14-month validity cap.

## Licence

| component | licence |
|---|---|
| `faxl-*.whl` + this repo's docs | [PolyForm Noncommercial 1.0.0](LICENSE.md) — free for noncommercial use as the licence defines it; commercial use needs a commercial licence from Gamakon Ltd (andrew@gamakon.ai) |
| `UltraDim-*.whl` | [proprietary](LICENSE-UltraDim.md) — licensed for use as a component of faxl only |

See also [NOTICE.md](NOTICE.md) (AI-training / text-and-data-mining rights
reserved).
