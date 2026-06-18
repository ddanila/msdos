---
name: Use build log file, not repeated makes
description: Run make once, redirect to a log file, then grep/analyze that log — never re-run full make just to grep differently
type: feedback
---

Run `make -k` once redirecting output to a build log file (e.g., `/tmp/build.log`), then analyze that log with grep/sed/awk. Do NOT re-run full `make -k` multiple times with different grep filters — each run takes minutes and wastes time.

**Why:** User was frustrated by repeated full builds just to grep with different arguments. Each `make -k` run is expensive.

**How to apply:** Always `make -k 2>&1 | tee /tmp/build.log` on first run, then `grep ... /tmp/build.log` for all subsequent analysis.
