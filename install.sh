#!/usr/bin/env bash
# faxl for Mac -- install, or upgrade what is already there.
#
#   git clone https://github.com/Gamakon/faxl-mac-community.git
#   cd faxl-mac-community
#   ./install.sh
#
# Run it again any time to upgrade: it pulls the latest release first.
#
# WHAT IT DOES
#   * If a faxl proxy is running, it upgrades the Python environment that
#     proxy runs from, then stops it -- waiting until it has fully exited, so
#     two copies of the model are never in memory at once -- and starts it
#     again with faxl's own launcher (which refuses to start a second copy).
#   * If none is running, it installs into ./faxl-env (creating it if needed)
#     and starts faxl.
#   * Either way: the newest wheels from this repository, everything faxl
#     runs on (mlx, mlx-vlm, mlx-whisper, ...), and ffmpeg (Homebrew) for
#     Voice to text's whole-recording transcript.
#   * Your licence, cache, models and settings are left exactly as they are.
#
# OPTIONS
#   --dry-run    say what would happen, change nothing
#   --no-start   install or upgrade, but do not start (or restart) faxl
#   --env DIR    install into this Python environment instead of the one a
#                running faxl uses (or ./faxl-env). A faxl running from a
#                different environment is then left alone, not restarted.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAXL_WHL="faxl-0.1.0-cp39-abi3-macosx_11_0_arm64.whl"
UD_WHL="ultradim-0.5.0-cp312-abi3-macosx_11_0_arm64.whl"
PORT="${FAXL_PORT:-8767}"
DRY=0; START=1; ENV_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --no-start) START=0 ;;
    --env) shift; ENV_DIR="${1:?--env needs a folder}" ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
fail() { printf '\nfaxl install stopped: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then say "   would run: $*"; else "$@"; fi; }

# ---- this machine --------------------------------------------------------
step "Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || fail "this installer is for macOS."
[ "$(uname -m)" = "arm64" ] || fail "faxl for Mac needs Apple silicon (M1 or later)."
say "   macOS on Apple silicon: ok"

# ---- the latest release --------------------------------------------------
step "Getting the latest release"
if [ -d "$HERE/.git" ] && command -v git >/dev/null 2>&1; then
  run git -C "$HERE" pull --ff-only || fail "git pull did not complete. Resolve it (git status), then run ./install.sh again."
else
  say "   not a git clone: using the wheels next to this script"
fi
[ -f "$HERE/$FAXL_WHL" ] || fail "$FAXL_WHL is not next to this script. Clone the repository and run ./install.sh from inside it."
[ -f "$HERE/$UD_WHL" ] || fail "$UD_WHL is not next to this script."

# ---- is faxl running? ----------------------------------------------------
# A proxy is an interpreter running `-m faxl.engine.faxl_proxy` -- matched on
# the program and its arguments, not on text anywhere in a command line.
proxy_pids() {
  ps -axo pid=,args= 2>/dev/null | awk '
    $2 ~ /(^|\/)[Pp]ython[0-9.]*$/ {
      for (i = 3; i < NF; i++)
        if ($i == "-m" && $(i + 1) == "faxl.engine.faxl_proxy") { print $1; break }
    }'
}
RUNNING_PID="$(proxy_pids | head -1)"
RUNNING_PY=""
if [ -n "$RUNNING_PID" ]; then
  RUNNING_PY="$(ps -o args= -p "$RUNNING_PID" | awk '{print $1}')"
  [ "$(proxy_pids | wc -l | tr -d ' ')" -gt 1 ] && say "   note: more than one faxl proxy is running; upgrading the first (pid $RUNNING_PID)"
fi

step "Finding your faxl"
OTHER_RUNNING=0
if [ -n "$ENV_DIR" ] && [ -n "$RUNNING_PY" ] && [ "$RUNNING_PY" != "$ENV_DIR/bin/python" ] \
   && [ "$RUNNING_PY" != "$ENV_DIR/bin/python3" ]; then
  # --env named another environment: install there, leave the running faxl
  OTHER_RUNNING=1
  say "   faxl is running (pid $RUNNING_PID) from $RUNNING_PY -- a different"
  say "   environment from --env; it is left alone and not restarted"
  RUNNING_PID=""; RUNNING_PY=""
fi
if [ -n "$RUNNING_PY" ]; then
  PY="$RUNNING_PY"
  say "   faxl is running (pid $RUNNING_PID) from $PY"
  say "   that environment will be upgraded, and faxl restarted"
else
  ENV_DIR="${ENV_DIR:-$HERE/faxl-env}"
  PY="$ENV_DIR/bin/python"
  [ "$OTHER_RUNNING" = 1 ] || say "   faxl is not running"
  if [ -x "$PY" ]; then
    say "   upgrading $ENV_DIR"
  else
    say "   installing into $ENV_DIR"
    BASE_PY=""
    for c in python3.13 python3.12 python3; do
      if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' 2>/dev/null; then
        BASE_PY="$(command -v "$c")"; break
      fi
    done
    [ -n "$BASE_PY" ] || fail "faxl needs Python 3.12 or newer. Install it (for example: brew install python@3.12), then run ./install.sh again."
    say "   using $BASE_PY ($("$BASE_PY" -c 'import sys; print(sys.version.split()[0])'))"
    run "$BASE_PY" -m venv "$ENV_DIR"
  fi
fi

# ---- install / upgrade ---------------------------------------------------
step "Installing faxl"
# The wheels are reinstalled every time: each release keeps the same filename
# and version, so without --force-reinstall pip would keep the old one. The
# dependencies are not forced (that would download mlx again for nothing):
# the second command only adds what is missing, such as mlx-whisper.
run "$PY" -m pip install --quiet --upgrade pip
run "$PY" -m pip install --quiet --force-reinstall --no-deps "$HERE/$FAXL_WHL" "$HERE/$UD_WHL"
run "$PY" -m pip install --quiet "${HERE}/${FAXL_WHL}[mac]" "$HERE/$UD_WHL"
if [ "$DRY" = 0 ]; then
  "$PY" -c 'import faxl, mlx_vlm, mlx_whisper, ultradim' 2>/dev/null \
    || fail "the install finished but faxl's pieces do not import in $PY. Run: $PY -c 'import faxl, mlx_vlm, mlx_whisper, ultradim' to see why."
  say "   faxl, mlx-vlm, mlx-whisper and ultradim: installed"
fi

# ---- ffmpeg --------------------------------------------------------------
step "ffmpeg (Voice to text)"
if command -v ffmpeg >/dev/null 2>&1; then
  say "   ffmpeg: already installed"
elif command -v brew >/dev/null 2>&1; then
  run brew install ffmpeg
else
  say "   ffmpeg is missing and Homebrew is not installed. Voice to text works,"
  say "   but its whole-recording transcript needs ffmpeg: install Homebrew"
  say "   (https://brew.sh), then: brew install ffmpeg"
fi

# ---- stop and start ------------------------------------------------------
if [ "$OTHER_RUNNING" = 1 ] && [ "$START" = 1 ]; then
  step "Done (not started)"
  say "   Another faxl is already running. Only one can run at a time (two copies"
  say "   of a model can crash the Mac): stop it first, then run ./install.sh again."
  exit 0
fi
if [ "$START" = 0 ]; then
  step "Done (not started: --no-start)"
  [ -n "$RUNNING_PID" ] && say "   faxl is still running the OLD version (pid $RUNNING_PID). Restart it to use the new one."
  exit 0
fi

if [ -n "$RUNNING_PID" ]; then
  step "Restarting faxl"
  say "   stopping pid $RUNNING_PID and waiting for it to exit (large models take a while to release memory)"
  if [ "$DRY" = 0 ]; then
    kill "$RUNNING_PID" 2>/dev/null || true
    waited=0
    while kill -0 "$RUNNING_PID" 2>/dev/null; do
      sleep 1; waited=$((waited + 1))
      [ "$waited" -eq 120 ] && fail "faxl (pid $RUNNING_PID) has not exited after 2 minutes. Wait for it to exit, then run ./install.sh again. Never start a second copy alongside it."
    done
    say "   stopped after ${waited}s"
  fi
else
  step "Starting faxl"
fi

LAUNCHER="$("$PY" -c 'import os, faxl.engine as e; print(os.path.join(os.path.dirname(e.__file__), "faxl_start.sh"))' 2>/dev/null || true)"
if [ "$DRY" = 1 ]; then
  say "   would start faxl with its launcher (FAXL_PYTHON=$PY)"
  exit 0
fi
[ -f "$LAUNCHER" ] || fail "faxl's launcher was not found in $PY's install."
FAXL_PYTHON="$PY" bash "$LAUNCHER" >/dev/null 2>&1 || true

say "   waiting for faxl to answer on port $PORT (loading a model can take minutes)"
for _ in $(seq 1 300); do
  if curl -s -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    HEALTH="$(curl -s -m 5 "http://127.0.0.1:$PORT/health")"
    step "faxl is running"
    "$PY" - "$HEALTH" "$PORT" <<'EOF'
import json, sys
h = json.loads(sys.argv[1]); port = sys.argv[2]
lic = h.get("licence") or {}
print(f"   console:  http://127.0.0.1:{port}/console")
print(f"   API:      http://127.0.0.1:{port}/v1   (any API key)")
print(f"   model:    {h.get('model') or 'none yet: pick one in the console'}")
if lic.get("licensed"):
    print(f"   licence:  {lic.get('customer')}, {int(lic.get('days_remaining') or 0)} days left")
else:
    print("   licence:  none yet: paste your key from faxl.ai into the console's")
    print("             Licence panel, then restart (without one nothing is cached)")
EOF
    exit 0
  fi
  sleep 2
done
fail "faxl did not answer within 10 minutes. Its log is ~/.faxl/logs/proxy.log -- the last lines say why."
