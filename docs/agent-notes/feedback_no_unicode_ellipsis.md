---
name: No unicode ellipsis in code or text
description: Never use the unicode horizontal ellipsis character `…` (U+2026) in code comments, commit messages, or any written text — use three ASCII dots `...` instead
type: feedback
originSessionId: 0cdbc900-a2ce-42fb-b7e4-c361a32f1de6
---
Don't write the unicode horizontal ellipsis `…` (U+2026) in code comments, commit messages, PR descriptions, or any other text. Always use three ASCII dots `...`.

**Why:** The unicode ellipsis is a non-ASCII character that can render incorrectly in some terminals/editors, breaks tools that expect ASCII source, and is just visual noise versus `...`. Same applies to the unicode em-dash `—` and similar typographic characters — prefer ASCII `--` or just `-`.

**How to apply:** When writing any text that goes into source/commit/PR — comments, documentation, commit messages, PR descriptions — use ASCII only. `...` not `…`. `--` not `—`. Plain ASCII quotes when describing code (the smart-quote rendering happens automatically in markdown / prose contexts where the user wants it; not in code).
