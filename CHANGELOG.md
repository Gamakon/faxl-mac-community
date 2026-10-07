# Changelog — faxl Mac community edition

What changed in each published wheel, and whether you need to re-download.

The wheel keeps the same filename every release, so to see which build you
are running:

    curl -s localhost:8767/health

From 2026-09-26 this is the PRODUCTION build and its life is your licence
key's, not the wheel's. `EXPIRY_EPOCH.txt` described the old time-limited
tester builds and no longer applies; `curl -s localhost:8767/api/licence`
tells you who a key is for and when it runs out.

---

## 2026-10-07 — a big model on a 64 GB Mac, model switching, and the token in the UI

**Re-download if you run Qwen3.8-Flash-Next, switch models from a client, or
have ever hit a gated HuggingFace repo.** If you run one model on one Mac and
have never seen a download refused, the cache works exactly as it did and there
is no hurry. The index wheel is unchanged.

**Qwen3.8-Flash-Next now fits a 64 GB Mac, and its cache works at all.** Two
separate faults. The model carries a 320-million-row lookup table -- 33.6 GiB,
45% of the checkpoint -- that was wired into RAM in full though roughly sixteen
rows are read per token. faxl now memory-maps it automatically: peak **76.2 ->
46 GiB**, load **27.4s -> ~10s**, output byte-identical. Separately, one
non-array scalar in its 48-layer cache made every checkpoint unserialisable, so
the prefix cache was silently inert on this model -- every long prompt re-read
in full, nothing in the console saying so. Both fixed.

**A client can switch the served model.** Name a different local model in the
`model` field and faxl switches to it and answers. Measured 6s for a 46 GiB
model down to a 19 GB one. A model this machine does not hold is a `400` with
`model_not_found` and the list of what it does have -- never a silent answer
from the wrong model, and never a download started behind your back.

**The HuggingFace token is in the console.** There was no field for it: a gated
repo failed with a traceback, and the only hint was a sentence telling you to go
and run `hf auth login` in a shell. There is now a pill beside the licence, and
a field in the cache & store drawer. It is stored `0600` in a file of its own,
never in `config.json`, and never sent back to the page -- the console shows
only whether a token is set and where it came from. An existing `HF_TOKEN` or
`hf auth login` still wins, and the UI says so rather than quietly losing to it.

**Generation speed, measured and shown.** Per request and per model, timed
first token to last -- the same span a client sees timing its own stream. The
figure faxl had been computing internally was wall-clock minus prefill, which
swept cache work into "decode" and understated generation speed on every warm
request: the warmer the hit, the worse the lie.

**The speculator's table now reaches disk.** It is harvested from every answer
and written every tenth, plus on a clean stop. Before this it only ever reached
disk on an explicit save nobody called, so a kill lost everything learned.
Drafting from the table is still off -- see "In progress" in the README.

Also: `faxl_reset.sh` to put an install back to new for testing, and an exo
section in the README that the last rewrite dropped.

Built from faxl-mac-dev `da221b4`, faxl-core `c865788`.

## 2026-10-01 — tool calls were returned malformed, and each turn now settles warm

**Re-download if you use faxl with an agent or any tool-calling client** — Claude
Code, mcode, or anything that sends `tools` and reads `tool_calls` back. On
Granite models those calls came back in a shape a correct client cannot parse,
and the failure did not look like ours. If you only send plain chat prompts,
nothing here affects you and there is no hurry. The index wheel is unchanged.

**Tool-call arguments were double-encoded.** Granite emits `arguments` inside its
`<tool_call>` markup as an object most of the time, but sometimes as a JSON
string. faxl re-encoded whatever it found, so the string case came back as a JSON
string wrapping a JSON string: `json.loads(arguments)` returned a `str` where the
OpenAI contract promises a dict.

What that cost is worth spelling out, because the symptom pointed somewhere else
entirely. A correct client stored the malformed call and replayed it as
conversation history on the next turn, where the unparseable arguments corrupted
turn state. In mcode it surfaced as *"Conversation history could not be safely
updated. Please retry."* — a client-side history error, with nothing naming the
response that caused it. It reproduced on a cache hit too, which ruled out the
timing explanations. It was debugged as a client bug first.

Fixed by decoding before re-encoding, which is what the Nemotron branch had
always done; Granite's was the only path missing it. Kimi and Ling were never
affected. A non-JSON string is now preserved as `{"_raw": ...}` rather than
discarded. Verified end to end through real `mcode exec` sessions: one tool call,
two chained, and a three-step chain, all with multi-turn history replay — 3/3,
no errors, confirmed by the team that reported it.

**Each answer is now checkpointed as it is delivered.** "Turn settle": the state
for the reply you just received is stored while you read it, so the next turn in
a conversation starts warm instead of paying for the assistant message it just
saw. Multi-turn chat and agent loops resume deeper, sooner. `FAXL_SETTLE=0` turns
it off.

**Vision ships, and it needs the `[mac]` extra.** This was true before and the
docs said otherwise; see the README. The loader is chosen by the model's own
`config.json`, so a vision model reads images rather than answering from a
placeholder — but only with `mlx-vlm` installed, which `[mac]` pulls. Install
without it and a photograph reaches the model as a placeholder and the answer is
invented. faxl now refuses to start on a vision model rather than do that
quietly.

**exo integration also ships**, and is inert unless you install and run exo
yourself. With no cluster, the console's exo page simply reports that exo is not
answering.

No expiry is compiled into this wheel: your licence key's own term is the only
clock, and when a key lapses the proxy keeps serving with the cache off.

## 2026-09-30 — UltraDim 0.5.0, and it installs on Python 3.13

**Re-download if you are on Python 3.13 or newer, or if the install failed
with "not a supported wheel on this platform".** Otherwise there is no hurry:
the faxl wheel is unchanged.

The shipped index wheel is now `ultradim-0.5.0-cp312-abi3-…`. The one before
it was tagged `cp312-cp312`, which declares CPython 3.12 only, so pip refused
to install it on 3.13+ — a new install on a current Mac stopped at the second
wheel. The engine was never the problem; the tag was.

    pip install './faxl-0.1.0-cp39-abi3-macosx_11_0_arm64.whl[mac]' \
                ./ultradim-0.5.0-cp312-abi3-macosx_11_0_arm64.whl

Both wheels are now `abi3`, so any CPython from 3.12 up works and the
instructions no longer pin `python3.12`. Verified on a clean 3.13 venv: both
wheels install and faxl, ultradim and mlx-vlm all import.

0.5.0 also drops a `numpy` dependency the previous wheel declared but never
imported, so the install pulls less.

## 2026-09-26 — the console becomes the product, and the build needs a key

**Re-download, and get a licence key.** This is the **production build**: the
cache does nothing without one. The proxy still serves and the console still
works without a key -- every prompt is processed cold -- but the speed-up is
what the key buys. Previous wheels here were time-limited tester builds that
needed no key; this one replaces that. Paste your key into the console's
Licence panel.

**The default model changed, and it is much smaller.**
`mlx-community/Qwen3-VL-4B-Instruct-4bit` -- 2.9 GB, against 34 GB for the
Granite model before it. It reads images as well as text, which is what the
new apps need, and it runs on any modern Mac.

**Install with the mac extras:**

    pip install './faxl-0.1.0-cp39-abi3-macosx_11_0_arm64.whl[mac]' \
                ./ultradim-0.5.0-cp312-abi3-macosx_11_0_arm64.whl

The `[mac]` matters: it pulls **mlx-vlm**, without which a photograph reaches
the model as a placeholder and the answer is invented rather than read. It
also pulls PyObjC, which is what lets you grant faxl access to **chosen
photographs** instead of your whole disk.

**New: a console with apps that work.**

- **Tag your camera roll** -- captions, scene descriptions, text in the
  image and keywords, written back into Photos so they are searchable.
  Photographs are chosen through macOS's own picker, so faxl reads only what
  you select. Watch the pipeline: every photo after the first reuses the
  cached instructions.
- **Voice to text** -- recorded and transcribed on the machine with Whisper.
  Needs `ffmpeg` (`brew install ffmpeg`); nothing else does.
- **Read the text (OCR)** and **Whiteboard to diagram**.

**Also in this build:** a restart always comes back up (a model that will not
load is reported on the page rather than leaving you with no console); the
store no longer refuses to write when a model has been swapped; and a stale
weights index no longer reads as a missing model.

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
