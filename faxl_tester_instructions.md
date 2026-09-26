# faxl — Tester Instructions

Thanks for testing faxl. This is the **production build**: it needs a
**licence key**, which you paste into the console. It runs fully offline —
the key is checked on your Mac, and nothing about your use is reported
anywhere.

Without a key the proxy still serves and the console still works; the cache
is simply off, so every prompt is processed from cold. That is the difference
the key buys, and it is worth seeing both ways round.

faxl is a caching proxy for local LLMs on Apple silicon, and a console with
working apps on top of it. When a prompt shares a prefix with one it has seen,
it skips re-processing that prefix — repeated prompts get their first token
back far faster, with **byte-identical** output.

The apps are the quickest way to see that: every photograph you tag sends the
same instructions, so the first one pays for them and the rest reuse the
state. The console shows the tokens it did not have to process.

## What you need
- A Mac with Apple silicon (M1–M4).
- **Python 3.12** (`brew install python@3.12` if missing).
- **ffmpeg**, for voice-to-text only (`brew install ffmpeg`). Everything else
  works without it.
- Disk: **3 GB** for the default model, plus room for the cache store. The
  store is capped at 60 GB by default (`FAXL_STORE_CAP_GB`); 8 GB is plenty
  for trying the apps.
- The two wheels shipped with this file: `faxl-…-arm64.whl` and
  `UltraDim-…-cp312-…-arm64.whl`.

## Install & run (copy-paste)

```bash
python3.12 -m venv faxl-env && source faxl-env/bin/activate
pip install './faxl-0.1.0-cp39-abi3-macosx_11_0_arm64.whl[mac]' \
            ./UltraDim-0.3.7-cp312-cp312-macosx_11_0_arm64.whl
faxl-proxy
```

The `[mac]` after the wheel filename pulls the Apple-silicon runtime: mlx, mlx-lm, **mlx-vlm** (the
vision half — without it a photograph reaches the model as a placeholder and
the answer is invented) and PyObjC, which is what lets you grant access to
**chosen photographs** rather than your whole disk.

Then open **http://127.0.0.1:8767/console**.

First run downloads the default model, `mlx-community/Qwen3-VL-4B-Instruct-4bit`
— **2.9 GB**, and it runs on any modern Mac. It reads images as well as text,
which is what the apps need. A different MLX model: pick one in the console,
or `export FAXL_MODEL=<mlx-community/repo>` before starting.

## Put your licence in

Open **http://127.0.0.1:8767/console**, find the **Licence** panel, paste the
key you were sent, and save. The page tells you who it is for and when it
runs out.

Nothing is sent anywhere: the key is a signed block of text, checked against
a public key compiled into the wheel. faxl never phones home, with or without
a key.

You can check it took:

```bash
curl -s localhost:8767/api/licence | python3 -m json.tool
```

Before the key, `/metrics` shows every request processed from cold. After it,
repeated prompts start hitting the cache — that difference is the product.

## Try the apps

Everything below runs on your Mac. No photograph, recording or document
leaves it, and there is no account to create.

**Tag your camera roll** — `/console/apps/cameraroll`
Press **Choose…** and pick some photographs; macOS shows its own picker, and
faxl can read only what you select. Then **Start tagging**. Each photograph
gets a caption, a scene description, any text in the image, and keywords —
written back into Photos if you leave that box ticked, so they become
searchable. Watch the pipeline: photographs move through it, and the panel
shows the tokens reused on every one after the first.

**Voice to text** — `/console/apps/voice2text`
Record, and it transcribes locally with Whisper (ffmpeg decodes the audio).
Long recordings are transcribed in pieces as you speak and then re-done whole
for the authoritative text.

**Read the text (OCR)** — `/console/apps/ocr`
Drop in a photograph of a page, receipt or sign; get clean text back.

**Whiteboard to diagram** — `/console/apps/whiteboard`
Photograph a hand-drawn diagram; get Mermaid source you can paste into a doc.

## Use it as a proxy
Point **any** OpenAI-compatible client at `http://127.0.0.1:8767/v1` (any api
key value; it's ignored). Send a request, then a **follow-up that extends the
same conversation** — the second one is where the cache pays, because it
contains the first as its prefix. The console's request feed shows, per
request, whether it hit and how many prompt tokens it skipped.

## What to report
- First-token latency: cold request vs a follow-up in the same conversation.
- Correctness: cached answers must be identical to uncached
  (`export FAXL_NOCACHE=1` + restart = same proxy with the cache off, for A/B).
- Your real workload: point your agent/app at the proxy and note the
  % of prompt tokens skipped (shown in the console).
- Anything that breaks or looks wrong: **andrew@gamakon.ai**

## Running it as a shared server (e.g. a lab Mac Studio)

One Mac serving several people is a supported setup, with a few things to
get right first.

**There is no authentication.** Any API key is accepted and `/console` is
open. The proxy binds to loopback (`127.0.0.1`) by default; setting
`FAXL_HOST=0.0.0.0` exposes it to the network and it prints a warning at boot.
Either:
- keep it on loopback and put Caddy or nginx in front with basic auth or a
  bearer-token check (recommended on a university network), or
- bind to the LAN and rely on the macOS firewall plus a trusted subnet
  (fine for a lab room, not campus-wide).

**Concurrency.** Inference runs one request at a time behind a lock; the
HTTP layer is threaded, so simultaneous callers queue rather than fail.
Streaming works through the queue. Latency stacks when several people submit
at once.

**Storage.** Put the store on the internal SSD. `FAXL_STORE_CAP_GB` (default
60) caps the store; at the cap, new checkpoints are skipped loudly while
existing ones keep serving. A Mac Studio with a large disk can go much
higher. Set `FAXL_METRICS` to a durable path (its default is under `/tmp`).

**Qwen.** `FAXL_MODEL=mlx-community/<Qwen repo>`. For Qwen3,
`FAXL_ENABLE_THINKING=0|1` sets the default thinking mode when a client does
not specify one. Qwen tokenizers do not need `FAXL_TRUST_REMOTE_CODE`.

**Attribution.** `FAXL_TENANT` labels telemetry; set it to your lab's name.

**Run under launchd** as a LaunchAgent for a dedicated user so it survives
reboots and crashes. Model load takes minutes after every start and the
store warm-starts, so restarts are always safe; stopping is a plain SIGTERM.
Save this as `~/Library/LaunchAgents/ai.faxl.proxy.plist` (edit the paths,
model and tenant), then `launchctl load ~/Library/LaunchAgents/ai.faxl.proxy.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>ai.faxl.proxy</string>
  <key>ProgramArguments</key>
  <array><string>/Users/faxl/faxl-env/bin/faxl-proxy</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>FAXL_HOST</key><string>127.0.0.1</string>
    <key>FAXL_PORT</key><string>8767</string>
    <key>FAXL_MODEL</key><string>mlx-community/Qwen3-32B-8bit</string>
    <key>FAXL_BLOBS</key><string>/Users/faxl/faxl-store</string>
    <key>FAXL_STORE_CAP_GB</key><string>400</string>
    <key>FAXL_METRICS</key><string>/Users/faxl/faxl-store/metrics.jsonl</string>
    <key>FAXL_TENANT</key><string>your-lab-name</string>
  </dict>
  <key>KeepAlive</key><true/>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/Users/faxl/faxl-proxy.log</string>
  <key>StandardErrorPath</key><string>/Users/faxl/faxl-proxy.log</string>
</dict></plist>
```

Stop the Mac sleeping: `sudo pmset -a sleep 0 disksleep 0`.

**Do not change** `FAXL_SEEDS`, `FAXL_CKPT_EVERY` or `FAXL_CKPT_RATIO` once the
store has content (they define the store namespace), and never delete the
store to fix a problem: stop, fix, restart.

**Wheel refreshes.** `pip install` the new wheel into the same venv, then
restart the service. The store carries over.

**Health.** `curl -s localhost:8767/health` and `/metrics`; the console at
`/console`.

## Using it from an AI agent
If Claude Code (or any MCP-capable agent) is doing the setup for you, point it
at [AGENTS.md](AGENTS.md) in this directory — full operating instructions plus
an MCP server (`faxl-mcp`, installed with the wheel) that exposes
start/stop/status/licence/metrics as typed tools.

## Notes
- Offline: nothing phones home; no licence server; prompts never leave your Mac.
- **The cache stores your prompts on disk.** Alongside the model state, it
  keeps the verbatim token-id prefix of every cached prompt (system message
  included) under `$FAXL_BLOBS/tokens/`. Those ids decode straight back to
  the prompt text. They are required: a hit is confirmed by comparing them
  byte-for-byte, which is what makes reuse exact rather than a hash guess.
  The files are written `0600` in a `0700` directory, so other users on the
  same Mac cannot read them, but treat the store as sensitive as the prompts
  that went into it. Nothing leaves your machine.
- This build stops accelerating ~12 months after it was built; ask for a fresh
  build (faxl.ai) if you need longer.
- The proxy serves on port **8767** (it was 8080 in builds before
  2026-09-15). `FAXL_PORT` overrides it.
- Licence keys: this build reads both the JSON keys the shop mints today and
  the older `customer|issued|expiry|action` format. Paste either into the
  console's Licence panel, or save it to `~/.faxl-licence` (or point
  `FAXL_LICENCE` at a file) and restart. Without a key the proxy serves
  normally with the cache off.
