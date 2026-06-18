---
name: cp437-byte-preserving-edits
description: MS-DOS .ASM/.INC sources are CP437/latin-1 with high-bit glyphs; the Edit/Write tools corrupt them by re-encoding as UTF-8. Edit byte-preserving instead.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 75a4ec5d-2e90-4df4-a646-46b051dcfb8d
---

The PC-DOS 4.0 sources (e.g. CMD/MODE/MAIN.ASM) contain CP437 high-bit
bytes -- box-drawing glyphs in banner comments (0xBA, 0xC4, 0xCD, etc.).
The Edit/Write tools read/write as UTF-8, so editing one line silently
re-encodes EVERY high-bit byte in the file (0xBA -> a multi-byte UTF-8
replacement sequence), producing a huge spurious diff and corrupting the
file's bytes.

**Why:** Caught it on MODE/MAIN.ASM -- a one-line `.FOR` change produced
~30 changed comment lines (box-drawing chars mangled). Build still passed
(corruption was in comments) but the bytes were wrong.

**How to apply:** For any MS-DOS source edit, edit **byte-preserving with
latin-1** rather than the Edit tool. Pattern:
```python
s=open(p,encoding='latin-1').read(); s=s.replace(old,new); open(p,'w',encoding='latin-1').write(s)
```
The earlier-this-session Python helpers (INDEINS.MAC, KBD.ASM, the .FOR
sweep) all used `encoding='latin-1'` and round-tripped bytes cleanly --
only the Edit-tool edits corrupted files. Verify any edit with
`git diff --stat` / byte compare; if unrelated comment lines changed,
it's encoding corruption -- restore from git and redo via latin-1.
Related: [[wasm-source-fix-patterns]].
