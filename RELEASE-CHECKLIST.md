# Release checklist — Mac community wheel

**Mandatory. Work top to bottom. Do not skip a step because it passed last
time.** Every item here exists because something shipped broken without it.

Two repos: the wheel is **built** in `faxl-mac-dev`, **published here**.
Source of truth for engine modules is `faxl-core`.

This is the canonical copy — releases are owned and pushed from this repo. A
copy also sits at `faxl-mac-dev/docs/RELEASE-CHECKLIST.md` for whoever is
building; if they diverge, this one wins.

---

## 1. Before building

- [ ] `git -C ../faxl-core status` and `git status` both clean. **Never build
      from a dirty tree** — other sessions edit these repos concurrently. Use
      `git worktree add --detach <dir> origin/main` and build there.
- [ ] Building from a **pushed** commit. A wheel built from unpushed work
      names a commit nobody else can see.
- [ ] Deliberate about what else you are shipping. `git log <last-release>..HEAD`
      — if it carries another line's work (exo, vision), decide that on
      purpose, not by accident.
- [ ] Engine sync gates green, **both lines**:
      `cd ../faxl-core && python3.12 tools/sync_engine.py --check mac && python3.12 tools/sync_engine.py --check nvidia`
- [ ] `cargo test --release` in `crates/faxl-py`.
- [ ] Dependency changes reviewed: `git diff <last-release>..HEAD -- crates/faxl-py/pyproject.toml crates/faxl-py/Cargo.toml`.

## 2. Build

- [ ] `find python -name __pycache__ -type d -prune -exec rm -rf {} +` first.
      Stale `.pyc` files have shipped inside a wheel before.
- [ ] Correct build mode. TESTER is `FAXL_TEST_EXPIRY=<epoch> FAXL_BOMB_ONLY=1`;
      COMMUNITY drops `BOMB_ONLY`; ENTERPRISE drops both. Getting this wrong
      ships a licence gate the recipient cannot satisfy — or none at all.
- [ ] `run_tests.sh` green (builds all three modes, tests the licence matrix).
- [ ] Record the expiry and check it is a year out, not a month.

## 3. Verify the artifact — not the source

- [ ] `unzip -l` the wheel: no `__pycache__`, licence files present, metadata
      correct.
- [ ] Install into a **fresh venv** and import.
- [ ] `faxl.licence_status()` reports the expected mode and expiry.
- [ ] **Licence matrix, with keys minted by the production signer**: JSON key,
      legacy key, and a key with entitlements. All must parse. (2026-09-15: a
      published wheel verified signatures then failed to parse the shop's own
      JSON keys.)
- [ ] **Run the proxy.** Boot it on a small model, confirm `warm-up:
      main-thread forward pass ok`, send a cold request, then a growing
      conversation, and confirm `warm(exact,confirmed,resume@N)` with N a
      multiple of 256. Reading a diff is not testing. (2026-09-11: every
      request failed on llama-architecture models and nothing caught it.)
- [ ] Token records `0600` in a `0700` directory. (2026-09-11: shipped 0644,
      world-readable verbatim prompts.)
- [ ] Console answers on `/console`, `/health`, `/metrics`.

## 4. Docs — the step that gets skipped

- [ ] **Grep for every port, path and filename you changed.** A port move is
      never one line. (2026-09-14: the default moved to 8767 and ten doc
      references still said 8080, including the launchd example and an SSH
      tunnel a tester was running.)
- [ ] `CHANGELOG.md` entry, leading with **whether the reader needs to
      re-download and why**. Most refreshes do not affect most people.
- [ ] `README.md` "Not in this build" section still true.
- [ ] Tester instructions and `AGENTS.md` match the wheel's actual behaviour,
      including anything the docs *claim* that the code does not do.
      (2026-09-11: the notes said prompts were not stored readably. They were.)
- [ ] Expiry file updated.

## 5. Publish

- [ ] Copy wheel + expiry into `faxl-mac-community`.
- [ ] Commit message states what changed, what you tested, and the source
      commit it was built from.
- [ ] Push.
- [ ] **Download the wheel back from GitHub and verify the sha256 matches the
      local file.** Publishing is not verified until the published artifact is.
- [ ] Install the downloaded copy in a clean venv and re-run the licence
      matrix against it.
- [ ] Tag the release and create a GitHub release pointing at the wheel.

## 6. After

- [ ] Tell the testers, naming anything that breaks their existing setup — a
      port change, a config path, a behaviour change.
- [ ] Append to `faxl-core/docs/messageboard.md` (UTC stamp, pull before
      appending, push straight after).
- [ ] Tell the other sessions if it touches something they own.
- [ ] Update any ticket this closes.

---

## Stop and ask AM

- The build mode is not obviously right for the audience.
- It would ship another line's work (exo, vision) to community testers.
- A test fails and the fix is not understood.
- It changes the licence verifier, the wire format, or the key envelope.
