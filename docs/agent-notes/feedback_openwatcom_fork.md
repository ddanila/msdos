---
name: Third-party tool issues go to our forks, never upstream
description: For OpenWatcom v2 and kvikdos bugs encountered during the MS-DOS WASM migration, reproduce and file against our ddanila/* forks; never touch the upstream repos
type: feedback
originSessionId: a1062260-5765-4ee0-a266-feb2ebf28315
---
When a WASM (or kvikdos, or other vendored-toolchain) bug is encountered
during this migration, prefer fixing it in the upstream tool rather than
working around it in our tree. OpenWatcom v2 has a long-term goal of being
able to build MASM-intended assembly sources, so our findings are useful
upstream.

**Forks the user maintains** — file all issues / PRs here:
- OpenWatcom v2 → `github.com/ddanila/open-watcom-v2`
- kvikdos → `github.com/ddanila/kvikdos`

The vendored binaries (e.g., `watcom/bin/`) are snapshots of upstream
`Current-build` releases, but all of our bug reports, reproducers, and
fixes go to the fork.

**Why:** The user maintains personal forks where migration-driven fixes
land (e.g., OpenWatcom PRs #1614 `&macro/&endm` and #1615 `PURGE` landed
there first). Filing directly against the upstream main repos is
explicitly not wanted — upstream interaction happens only when the user
decides to push fork changes.

**How to apply:**
- When a tool bug is reproducible, package a minimal reproducer and open
  an issue at the matching fork's issues page (use the `gh` CLI or web UI).
- Never file issues, comments, or PRs against `open-watcom/open-watcom-v2`
  or the upstream kvikdos repo.
- Do not push to upstream remotes on any of these repos.
