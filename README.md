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

> **Publishing a wheel here?** Follow
> [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) — mandatory, top to bottom.
> Every item on it exists because something shipped broken without it.

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

**A speculator that learns from your own sessions.** Separately from the cache,
faxl keeps a table of what usually follows what, built from every generation it
has served. With it, the model can be handed several likely next tokens at once
and confirm or reject them in a single pass instead of computing them one at a
time. It is always learning -- the table fills whether or not you use it -- and
it gets better the longer faxl has been running, because it has seen more of
your work. Measured on this line: **1.3x to 2.2x** faster generation once the
table has something to say.

Using it is your choice, and the trade is worth stating plainly. The prefix
cache above is lossless: same text, every time. The speculator is not quite --
every token still comes from the model itself, so quality is unaffected, but
where two continuations are near-equally likely it may settle on the other one,
so a run is not guaranteed to reproduce an unaccelerated run word for word. If
you are running evals, regression tests or anything that diffs output, leave it
off. If you want the model to be faster, turn it on.

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

The model register page and the console's power controls are on the development
line and are not in the published wheel.

**Vision ships.** The loader is chosen by the model's own `config.json`, not by a
flag, so a vision model such as the shipped `Qwen3-VL` reads images rather than
answering from a placeholder. It needs `mlx-vlm` installed — see Install below;
without it the proxy refuses to start on a vision model rather than quietly
inventing captions.

**exo** integration ships too, and is inert unless you install and run exo
yourself. With no cluster the console's exo page simply reports exo is not
answering.

## Install

See [faxl_tester_instructions.md](faxl_tester_instructions.md). Short version:
Python 3.12, `pip install` the two wheels with the **`[mac]`** extra — which
pulls `mlx-vlm`, so images are read rather than invented — then run
`faxl-proxy`.

**AI agents:** read [AGENTS.md](AGENTS.md) — full operating instructions,
plus an MCP server (`faxl-mcp`, installed with the wheel; registered by the
included [.mcp.json](.mcp.json)) exposing start/stop/status/licence/metrics
as typed tools.

## Quick reference

Start it:

```sh
faxl-proxy            # or: python -m faxl.engine.faxl_proxy
```

Backend and model come from `~/.faxl/config.json` (pick a model in the
console the first time), the licence key from `~/.faxl`, and the cache store
lives under the path shown on the console's cache panel.

**Port:** `8767` — override with `FAXL_PORT`. Binds loopback only
(`127.0.0.1`).

**For clients (OpenAI-compatible):**

| | |
|---|---|
| base URL | `http://127.0.0.1:8767/v1` |
| endpoint | `POST /v1/chat/completions` |
| model | whatever the proxy serves, e.g. `mlx-community/granite-4.0-h-small-8bit` |
| api key | anything — it is ignored; the licence file is the auth |

So for any OpenAI-style client: change the base URL, nothing else. Streaming
and tools both supported.

**Console (human view):** `http://faxl.localhost:8767/console` — or
`http://127.0.0.1:8767/console`.

**Other endpoints:** `/health`, `/metrics` (JSON counters), `/v1/models`.

**Useful env switches:** `FAXL_MODEL` (override the model),
`FAXL_NOCACHE=1` (cache off, for A/B), `FAXL_SETTLE=0` (turn settle off —
on by default, it checkpoints each answer as it is delivered so the next
turn starts warm), `FAXL_STORE_CAP_GB` (store size).

## Shared server

Running one Mac (e.g. a lab Mac Studio) as a long-lived proxy for several
people is supported. Note the proxy has **no authentication** and binds to
loopback by default; the tester guide's
[shared server section](faxl_tester_instructions.md#running-it-as-a-shared-server-eg-a-lab-mac-studio)
covers exposure, concurrency, storage caps, Qwen settings and a launchd
service definition.

## Release notes

[CHANGELOG.md](CHANGELOG.md) — what changed in each wheel and whether you need
to re-download. The filename does not change between releases; check `/health`
to see which build you have.

## Current release

- `faxl-0.1.0-…-arm64.whl` — the **production build**. A licence key from
  faxl.ai turns the cache on; the key's own expiry is the only clock. Without
  a key the proxy still proxies and simply stops accelerating — nothing
  breaks, every request just runs cold.
- `ultradim-0.5.0-…-abi3-….whl` — the index wheel.

Both wheels are `abi3`: any CPython from 3.12 up.

## Licence

| component | licence |
|---|---|
| `faxl-*.whl` + this repo's docs | [PolyForm Noncommercial 1.0.0](LICENSE.md) — free for noncommercial use as the licence defines it; commercial use needs a commercial licence from Gamakon Ltd (andrew@gamakon.ai) |
| `UltraDim-*.whl` | [proprietary](LICENSE-UltraDim.md) — licensed for use as a component of faxl only |

See also [NOTICE.md](NOTICE.md) (AI-training / text-and-data-mining rights
reserved).
