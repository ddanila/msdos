---
name: Build metrics reliability
description: Error count alone is not a reliable metric for WASM migration progress — crashes, early bail-outs, and newly-revealed errors skew the number
type: feedback
---

Total error count is not a reliable single metric for tracking WASM migration progress. Fixing a crash (e.g. segfault) can increase the error count because previously-crashing files now run to completion and report their real errors.

**Why:** Observed when fixing 61 WASM segfaults via `invoke` → `do_invoke` rename — error count went from 3401 to 4053 even though clean file count improved (94→97) and failed targets decreased (433→431).

**How to apply:** Track multiple metrics together: clean file count, segfault count, failed target count. Don't report error count as the primary progress indicator. When comparing builds, always compare the same WASM binary version.
