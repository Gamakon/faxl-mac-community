# Changelog — faxl Mac community edition

What changed in each published wheel, and whether you need to re-download.

The wheel keeps the same filename every release, so check `EXPIRY_EPOCH.txt`
or `curl -s localhost:8767/health` to see which build you are running — the
expiry date is one year after the build date.

---

## 2026-09-15 — reads the shop's JSON licence keys

**Re-download if you have a licence key.** Keys minted from 2026-09-15 use a
JSON payload. An older wheel verifies the signature, then fails to parse it,
so a valid licence is refused with `expected 4 payload fields, got 1` and no
indication why. Both formats are accepted; older keys are not deprecated.

- Licence payloads may now be JSON, carrying `customer`, `issued`, `expiry`
  and optionally `action`, `product`, `tier`, `seats` and `features`. The
  envelope is unchanged: one line, base64url, Ed25519, `~/.faxl-licence`.
- `seats` is advisory. Verification is offline with no phone-home, so it is
  recorded for reference and is not an enforced limit.
- **The proxy now serves on port 8767, not 8080.** 8080 collides with almost
  everything a developer runs. `FAXL_PORT` overrides it. Update any client
  config, SSH tunnel or launchd plist that names the old port.

## 2026-09-11 — llama-family crash, and prompt-store permissions

**Re-download if you run a llama-architecture model.** Every request failed.

- **Fixed: `RuntimeError: There is no Stream(gpu, N) in current thread` on
  every request.** `mlx_lm` binds lazy state to a thread-local stream on the
  first forward pass, and the proxy never ran one on the main thread, so the
  first request bound it to an arbitrary worker. llama-family models then
  failed on every subsequent request; hybrids such as the default granite did
  not, which is why it went unnoticed. The proxy now runs a warm-up pass at
  boot and logs `warm-up: main-thread forward pass ok`.
- **Fixed: token records shipped world-readable (`0644`).** The store keeps
  the verbatim token-id prefix of every cached prompt, system message
  included, and those ids decode straight back to the prompt. They are
  required — the byte-confirm compares against them, which is what makes a hit
  exact rather than a hash guess — so the fix is permissions, not removal.
  Files are now `0600` inside a `0700` directory, and an existing store is
  re-moded at boot (`token records re-moded to 0600: N tightened`).
- Docs corrected: the notes previously claimed the cache stored "not readable
  prompt text", which was false. Disk guidance now accounts for the store,
  roughly 110 KB per token, rather than the model download alone.
- Prefix-hash throughput corrected to 0.031 µs/token; the documented 0.18 was
  about 6x pessimistic.

## 2026-09-08 — licensing and packaging

No behavioural change to the cache.

- Both wheels carry correct licence metadata. faxl is PolyForm Noncommercial
  1.0.0; UltraDim ships `LICENSE-UltraDim.md`, where it previously declared
  nothing at all.
- `LICENSE.md` gained the `Required Notice:` line PolyForm needs to function.
- `BOMB_EPOCH.txt` renamed `EXPIRY_EPOCH.txt`. It holds the expiry, not the
  build date.
- Telemetry proto namespace renamed to `faxl.telemetry.v1`. Wire format
  unchanged.
- Added a shared-server guide covering exposure, concurrency, store caps and a
  launchd service definition.

## 2026-09-02 — multi-model store safety

- Checkpoints are keyed and verified under a namespace of model plus config,
  so several models can share one store and can never serve each other's
  state. A store written under different settings is refused loudly at boot
  rather than silently mixed.

## 2026-09-01 — store management and console

- Scored store eviction under a size cap, with durable usage counters.
- Cache-contents scatter plot and an adaptive chart interval on the console.
- MCP server (`faxl-mcp`) and `AGENTS.md`, so an agent can operate the proxy
  through typed tools.

## 2026-08-31 — first tester release

Time-limited build, no licence key required, stops accelerating twelve months
after build. The proxy keeps serving after that; every prompt is processed
cold.
