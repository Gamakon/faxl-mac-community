#!/usr/bin/env bash
# faxl for Mac -- upgrade an existing install, or install fresh. One script for both.
#
#   git clone https://github.com/Gamakon/faxl-mac-community.git
#   cd faxl-mac-community
#   ./upgrade_install.sh
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
PORT=8767          # faxl's port, always: clients, agents and the docs all use it
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
command -v curl >/dev/null 2>&1 || fail "curl is missing (it ships with macOS). Reinstall Apple's command line tools: xcode-select --install"
if ! command -v git >/dev/null 2>&1; then
  say "   git is not installed. It comes with Apple's command line tools:"
  say "     xcode-select --install"
  say "   (only needed to fetch updates; carrying on with the files already here)"
fi
HAVE_BREW=0; command -v brew >/dev/null 2>&1 && HAVE_BREW=1
# A Python of 3.12 or newer, for a new environment. Installed with Homebrew
# when there is none and Homebrew is here; otherwise said, with where to get it.
find_python() {
  for c in python3.13 python3.12 /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' 2>/dev/null; then
      command -v "$c"; return 0
    fi
  done
  return 1
}

# ---- the latest release --------------------------------------------------
step "Getting the latest release"
if [ -d "$HERE/.git" ] && command -v git >/dev/null 2>&1; then
  run git -C "$HERE" pull --ff-only \
    || say "   could not fetch updates (no internet, or local changes) -- installing the release already here"
else
  say "   not a git clone: using the wheels next to this script"
fi
[ -f "$HERE/$FAXL_WHL" ] || fail "$FAXL_WHL is not next to this script. Clone the repository and run ./upgrade_install.sh from inside it."
[ -f "$HERE/$UD_WHL" ] || fail "$UD_WHL is not next to this script."

# ---- is faxl running? ----------------------------------------------------
# A faxl proxy is an interpreter running `-m faxl.engine.faxl_proxy` (how
# faxl's launcher and the console start it) OR the `faxl-proxy` command (how
# the README starts it: `python .../bin/faxl-proxy`). Matched on the program
# and its arguments, never on text anywhere in a command line.
proxy_pids() {
  ps -axo pid=,args= 2>/dev/null | awk '
    $2 ~ /(^|\/)[Pp]ython[0-9.]*$/ {
      for (i = 3; i <= NF; i++) {
        if (i < NF && $i == "-m" && $(i + 1) == "faxl.engine.faxl_proxy") { print $1; break }
        if ($i ~ /(^|\/)faxl-proxy$/) { print $1; break }
      }
    }
    $2 ~ /(^|\/)faxl-proxy$/ { print $1 }'
}
port_pid() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true; }
# faxl run as a launchd service (the shared-server setup) comes straight back
# when killed, so it is restarted through launchd instead.
LAUNCHD_LABEL=""
if launchctl list 2>/dev/null | awk '{print $3}' | grep -qx "ai.faxl.proxy"; then
  LAUNCHD_LABEL="ai.faxl.proxy"
fi
RUNNING_PID="$(proxy_pids | head -1)"
RUNNING_PY=""
if [ -n "$RUNNING_PID" ]; then
  # WHICH ENVIRONMENT IS IT RUNNING FROM? Read from the faxl files the
  # process has open (.../ENV/lib/pythonX.Y/site-packages/faxl/...), not from
  # its command line: Homebrew's Python re-executes itself as
  # .../Python.app/Contents/MacOS/Python, so the command line names the base
  # Python and an upgrade would land there instead of in the environment.
  FAXL_SO="$(lsof -p "$RUNNING_PID" -Fn 2>/dev/null | sed -n 's/^n//p' | grep -m1 '/site-packages/faxl/' || true)"
  if [ -n "$FAXL_SO" ]; then
    RUNNING_PY="${FAXL_SO%%/lib/python*}/bin/python"
  else
    RUNNING_PY="$(ps -o args= -p "$RUNNING_PID" | awk '{print $1}')"
    # started as `.../bin/faxl-proxy`: the environment's Python sits beside it
    case "$RUNNING_PY" in */faxl-proxy) RUNNING_PY="$(dirname "$RUNNING_PY")/python3" ;; esac
  fi
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
if [ -n "$RUNNING_PY" ] && [ ! -x "$RUNNING_PY" ]; then
  # THE RUNNING FAXL'S ENVIRONMENT HAS BEEN DELETED -- typically a fresh
  # clone over the old folder. The process keeps running from the deleted
  # files; there is nothing left to upgrade. Install a new environment here,
  # then replace the orphaned faxl with it (stop, wait, start).
  say "   faxl is running (pid $RUNNING_PID), but its environment is gone:"
  say "   $RUNNING_PY no longer exists (the folder was probably deleted or re-cloned)."
  say "   A new environment will be installed, and that faxl replaced by the new one."
  RUNNING_PY=""
fi
if [ -n "$RUNNING_PY" ]; then
  PY="$RUNNING_PY"
  say "   faxl is running (pid $RUNNING_PID) from $PY"
  say "   that environment will be upgraded, and faxl restarted"
else
  ENV_DIR="${ENV_DIR:-$HERE/faxl-env}"
  PY="$ENV_DIR/bin/python"
  [ "$OTHER_RUNNING" = 1 ] || [ -n "$RUNNING_PID" ] || say "   faxl is not running"
  if [ -e "$ENV_DIR" ] && ! { [ -x "$PY" ] && "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' 2>/dev/null; }; then
    say "   $ENV_DIR is there but broken or on Python older than 3.12: rebuilding it"
    run rm -rf "$ENV_DIR"
  fi
  if [ -x "$PY" ] && [ -e "$ENV_DIR" ]; then
    say "   upgrading $ENV_DIR"
  else
    say "   installing into $ENV_DIR"
    BASE_PY="$(find_python || true)"
    if [ -z "$BASE_PY" ] && [ "$HAVE_BREW" = 1 ]; then
      say "   no Python 3.12 or newer here: installing it with Homebrew"
      run brew install python@3.12
      BASE_PY="$(find_python || true)"
      [ "$DRY" = 1 ] && [ -z "$BASE_PY" ] && BASE_PY="/opt/homebrew/bin/python3.12"
    fi
    [ -n "$BASE_PY" ] || fail "faxl needs Python 3.12 or newer and none is installed. Install Homebrew (https://brew.sh) and run ./upgrade_install.sh again, or install Python from https://www.python.org/downloads/macos/"
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
PIPFAIL="pip could not finish. The first install downloads about 1 GB (mlx and friends): check the internet connection, then run ./upgrade_install.sh again."
run "$PY" -m pip install --quiet --upgrade pip || say "   (pip itself could not be upgraded; carrying on)"
run "$PY" -m pip install --quiet --force-reinstall --no-deps "$HERE/$FAXL_WHL" "$HERE/$UD_WHL" || fail "$PIPFAIL"
run "$PY" -m pip install --quiet "${HERE}/${FAXL_WHL}[mac]" "$HERE/$UD_WHL" || fail "$PIPFAIL"
if [ "$DRY" = 0 ]; then
  "$PY" -c 'import faxl, mlx_vlm, mlx_whisper, ultradim' 2>/dev/null \
    || fail "the install finished but faxl's pieces do not import in $PY. Run: $PY -c 'import faxl, mlx_vlm, mlx_whisper, ultradim' to see why."
  say "   faxl, mlx-vlm, mlx-whisper and ultradim: installed"
fi

# ---- ffmpeg --------------------------------------------------------------
step "ffmpeg (Voice to text)"
if command -v ffmpeg >/dev/null 2>&1; then
  say "   ffmpeg: already installed"
elif [ "$HAVE_BREW" = 1 ]; then
  run brew install ffmpeg || say "   ffmpeg did not install; Voice to text still works, without its whole-recording transcript"
else
  say "   ffmpeg is missing and Homebrew is not installed. Voice to text works,"
  say "   but its whole-recording transcript needs ffmpeg: install Homebrew"
  say "   (https://brew.sh), then: brew install ffmpeg"
fi

# ---- stop and start ------------------------------------------------------
if [ "$OTHER_RUNNING" = 1 ] && [ "$START" = 1 ]; then
  step "Done (not started)"
  say "   Another faxl is already running. Only one can run at a time (two copies"
  say "   of a model can crash the Mac): stop it first, then run ./upgrade_install.sh again."
  exit 0
fi
if [ "$START" = 0 ]; then
  step "Done (not started: --no-start)"
  [ -n "$RUNNING_PID" ] && say "   faxl is still running the OLD version (pid $RUNNING_PID). Restart it to use the new one."
  exit 0
fi

# STOP EVERYTHING ON THE WAY: every faxl proxy, and whatever holds the port.
# Each is asked to stop (SIGTERM) and waited for -- a model-sized process
# frees its memory as it exits, and starting the new faxl before then puts two
# copies of the model in RAM -- and only forced (SIGKILL) after 60 seconds.
# stop_pid PID WHAT GRACE: SIGTERM, wait, SIGKILL after GRACE seconds.
stop_pid() {
  pid="$1"; what="$2"; grace="$3"
  say "   stopping $what (pid $pid): $(ps -o args= -p "$pid" 2>/dev/null | cut -c1-90)"
  [ "$DRY" = 1 ] && return 0
  kill "$pid" 2>/dev/null || true
  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if [ "$waited" -eq "$grace" ]; then
      say "   pid $pid has not exited after ${grace}s: forcing it"
      kill -9 "$pid" 2>/dev/null || true
    fi
    [ "$waited" -ge $((grace + 30)) ] && fail "pid $pid would not stop. Restart the Mac, then run ./upgrade_install.sh again."
  done
  say "   stopped after ${waited}s"
}
if [ -n "$LAUNCHD_LABEL" ]; then
  step "Restarting faxl (launchd service $LAUNCHD_LABEL)"
else
  step "Stopping the old faxl and starting the new one"
fi
if [ -z "$LAUNCHD_LABEL" ]; then
  # Every faxl, gracefully: a model-sized process frees its memory as it
  # exits, and the new one must not load the model before then.
  STOPPED=" "
  for pid in $(proxy_pids); do stop_pid "$pid" "faxl" 60; STOPPED="$STOPPED$pid "; done
  # Then port 8767 itself: faxl belongs there and nothing else does. A faxl
  # this script did not recognise is still stopped gracefully; anything
  # else is killed off.
  holder="$(port_pid)"
  case "$STOPPED" in *" $holder "*) holder="" ;; esac
  if [ -n "$holder" ]; then
    if ps -o args= -p "$holder" 2>/dev/null | grep -q "faxl"; then
      stop_pid "$holder" "faxl on port $PORT" 60
    else
      stop_pid "$holder" "$(ps -o comm= -p "$holder" 2>/dev/null | xargs basename 2>/dev/null) on port $PORT (not faxl)" 10
    fi
  fi
  if [ "$DRY" = 0 ] && [ -n "$(port_pid)" ]; then
    fail "port $PORT is still in use by pid $(port_pid) after stopping it. Restart the Mac, then run ./upgrade_install.sh again."
  fi
  [ -z "$(proxy_pids)$(port_pid)" ] && say "   nothing of the old faxl is left; port $PORT is free"
fi
if [ -n "$LAUNCHD_LABEL" ]; then
  run launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_LABEL"
  [ "$DRY" = 1 ] && exit 0
else
LAUNCHER="$("$PY" -c 'import os, faxl.engine as e; print(os.path.join(os.path.dirname(e.__file__), "faxl_start.sh"))' 2>/dev/null || true)"
if [ "$DRY" = 1 ]; then
  say "   would start faxl with its launcher (FAXL_PYTHON=$PY)"
  exit 0
fi
[ -f "$LAUNCHER" ] || fail "faxl's launcher was not found in $PY's install."
FAXL_PYTHON="$PY" bash "$LAUNCHER" >/dev/null 2>&1 || true
fi

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
