# faxl — Mac community releases

**faxl** (faxl.ai, Gamakon Ltd) is a caching proxy for local LLM inference on
Apple silicon: it saves the model's working state, verifies byte-for-byte when
a request can reuse it, and skips the prompt processing already paid for.
Byte-identical output; the whole engine ships inside the wheel — install and
run `faxl-proxy`, console at `/console`.

This repo carries the **released wheels** for the Mac community edition.
Source lives in the private faxl repos; this is a release target.

## Install

See [faxl_tester_instructions.md](faxl_tester_instructions.md). Short version:
Python 3.12, `pip install` the two wheels + `mlx mlx-lm`, run `faxl-proxy`.

**AI agents:** read [AGENTS.md](AGENTS.md) — full operating instructions,
plus an MCP server (`faxl-mcp`, installed with the wheel; registered by the
included [.mcp.json](.mcp.json)) exposing start/stop/status/licence/metrics
as typed tools.

## Current release

- `faxl-0.1.0-…-arm64.whl` — **time-limited tester build** (no licence key
  needed; stops accelerating ~12 months after build; the proxy itself keeps
  working). Build epoch in `BOMB_EPOCH.txt`.
- `UltraDim-0.3.7-…-cp312-….whl` — the index wheel (Python 3.12).

Licensed builds (named 1-year keys from faxl.ai) replace the tester build at
launch; monthly wheel refreshes carry a 14-month validity cap.

## Licence

The faxl community wheel is distributed under the
[PolyForm Noncommercial License 1.0.0](LICENSE.md): free for noncommercial
use as the licence defines it. Commercial use requires a commercial licence
from Gamakon Ltd — andrew@gamakon.ai. UltraDim is a separate proprietary
Gamakon product distributed alongside for use with faxl only.
