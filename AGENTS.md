# faxl — instructions for AI agents

You are reading the distribution directory of **faxl** (faxl.ai, Gamakon Ltd),
a caching proxy for local LLM inference on Apple silicon. It saves the model's
working state to disk, and when a new request starts with a prompt prefix the
model has already processed, it verifies the match byte-for-byte and skips
that prefix — the model computes only the new tokens. Output is byte-identical
to running without the cache.

This file is self-sufficient: everything below can be done by hand with a
shell. An MCP server is also included (see "MCP server" below) if your
environment supports typed tools.

## Install (once per machine)

Apple silicon Mac, Python 3.12 (the UltraDim wheel is cp312-exact; the faxl
wheel is abi3 3.9+ — 3.12 satisfies both).

```sh
pip install ./faxl-*.whl          # cache core + the whole engine
pip install ./UltraDim-*.whl      # the index (note the capital U and D)
pip install mlx mlx-lm
```

Both Gamakon wheels are in THIS directory — neither is on PyPI. Installing
the faxl wheel gives you two commands: `faxl-proxy` (the proxy) and
`faxl-mcp` (the MCP server).

## Run

```sh
export FAXL_BLOBS=~/faxl-store    # REQUIRED: the persistent cache store.
                                  # The default is /tmp — volatile, and the
                                  # proxy warns at boot. Always set this.
export FAXL_MODEL=mlx-community/granite-4.0-h-small-8bit   # any mlx_lm model
faxl-proxy                        # serves :8767; first model load takes minutes
```

Then point any OpenAI-compatible client at `http://localhost:8767/v1` (any
api key string is accepted). A live dashboard is at
`http://localhost:8767/console`.

## MCP server (typed tools, optional)

Register the included server — from this directory Claude Code picks up
`.mcp.json` automatically, or register globally:

```sh
claude mcp add faxl -- faxl-mcp
```

If `faxl-mcp` is not on PATH, run `python3 -m faxl.engine.faxl_mcp` with the
interpreter the faxl wheel is installed into.

Tools:

| tool | does |
|---|---|
| `faxl_status` | pid + `/health` (includes the licence block) |
| `faxl_start` | start the proxy in the background; **requires `blobs`** (persistent store dir); model load can take minutes |
| `faxl_stop` | SIGTERM the proxy; the store persists and a restart warm-starts |
| `faxl_install_licence` | write a licence key to the key file (mode 600); restart to load |
| `faxl_metrics` | cache metrics: hits, hit_rate, prefill_skipped/paid |

The server shells out to the same commands documented in this file — nothing
it does is unavailable by hand.

## Verify the cache actually works

1. `curl -s localhost:8767/health` → `status: ok`.
2. Run a GROWING CONVERSATION, not a repeat. Sending the identical request
   twice is NOT a valid test — a trivial response memoizer would pass it.
   Instead: send a chat request with a long context (≥ ~1,100 tokens — a few
   pages of document text) and a question; then send a SECOND request that is
   the same conversation EXTENDED (prior messages + the assistant reply + a
   new, different question). The second request has content the proxy has
   never seen — only its prefix is shared. Its response's `faxl.cache` field
   must read `warm(exact,confirmed,resume@N,...)` with N a multiple of 256,
   and `prefilled_tokens` must be roughly the new tokens only, far below the
   total prompt length. A third extending turn should resume deeper.
3. `curl -s localhost:8767/metrics` → `hits`, `hit_rate`, `prefill_skipped`.

Correctness invariants — report a defect if either fails:
- a warm `resume@` that is NOT a multiple of 256;
- warm output not byte-identical to cold output for the same request at
  `temperature: 0`.

Do NOT quote identity-repeat latencies as the cache's benefit. Real multi-turn
traffic is the honest measure (the reference run cut paid prompt processing
62% over 5 turns; generation time is untouched by any cache).

## Licence

The current release in this directory is a **time-limited tester build**: it
needs NO licence key. It stops accelerating about 12 months after its build
date (expiry as a unix epoch in `EXPIRY_EPOCH.txt`); the proxy itself keeps serving, every prompt
processed cold. Named 1-year keys come from faxl.ai.

With a licensed build, the cache does nothing without a valid key: save the
key text to `~/.faxl-licence` (or point `FAXL_LICENCE` at it), restart the
proxy, and check `curl -s localhost:8767/health` — the `licence` block shows
`licensed`, `customer`, `days_remaining`.

A key is a single line, `<payload>.<signature>`, base64url, Ed25519-signed.
Leading `#` comment lines in the file are ignored. This build reads **both**
payload formats and tells them apart by their first byte:

- **JSON** (what the shop mints now) — carries `customer`, `issued`, `expiry`
  and optionally `action`, `product`, `tier`, `seats`, `features`. Timestamps
  are unix epoch seconds.
- **Legacy** `customer|issued|expiry|action` — still valid, not deprecated.

`seats` is advisory and is never enforced: verification is offline with no
phone-home, so it records what was bought, it does not limit anything. A build
older than 2026-09-15 rejects a JSON key with `expected 4 payload fields`.

## Settings that are safe vs. NOT safe to change

Safe: `FAXL_MODEL` (per-model states coexist in one store — every checkpoint
is keyed and verified under a namespace of model+config, so models can never
serve each other's state), `FAXL_BLOBS` (the store; `FAXL_DB` defaults to
`$FAXL_BLOBS/ultradim_db`), `FAXL_NOCACHE=1` (bypass, for A/B comparisons),
`FAXL_LICENCE`.

**Namespace-defining** — changing these puts you in a new namespace, so an
existing store's checkpoints stop being served (loudly, at boot — never
corruption): `FAXL_SEEDS`, `FAXL_CKPT_EVERY`, `FAXL_CKPT_RATIO`. Never
change them to work around a problem. A store written by an older faxl
loads only after a one-time `FAXL_NS_ADOPT=1` boot — set it only if the
store was written by exactly the current model and settings.

**Never delete the store to "fix" an issue unless the operator asks — it is
the accumulated value.** Stopping and restarting the proxy is always safe:
the store is persistent and a restarted proxy warm-starts from it.

## The store holds your prompts

The store keeps the verbatim token-id prefix of every cached prompt (system
message included) under `$FAXL_BLOBS/tokens/`; those ids decode straight back
to the prompt text. This is REQUIRED — the byte-confirm compares against them,
which is what makes a hit exact rather than a hash guess. Files are written
`0600` inside a `0700` directory, and a store written by an older build is
re-moded at boot (`token records re-moded to 0600: N tightened`). Nothing
leaves the machine, but treat the store as being as sensitive as the prompts
that went into it.

## Troubleshooting

| symptom | meaning | action |
|---|---|---|
| every request `cold`, health `licensed: false` | missing/expired key (licensed builds) | install a valid key, then RESTART — the key is read once at startup |
| every request `cold`, licence fine | prompts don't share prefixes, or under 64 tokens | expected — the cache only helps repeated prefixes |
| `!! VOLATILE STORE` at boot | store under /tmp | set `FAXL_BLOBS` to a real path |
| `FATAL: the 'faxl' wheel is not installed` | wrong interpreter | pip install the wheels into the SAME python that runs the proxy |
| boot hangs minutes at model load | a 30GB+ model paging in | normal first time; wait |
| `resume@` not a multiple of 256 | grid invariant violated | defect — capture logs, report to Gamakon |
| `RuntimeError: There is no Stream(gpu, N) in current thread` on every request | pre-2026-09-11 build: no main-thread warm-up, so mlx_lm bound lazy state to a worker thread (llama-family archs only) | fixed — use a build whose boot log prints `warm-up: main-thread forward pass ok` |

Commercial licensing and support: andrew@gamakon.ai.
