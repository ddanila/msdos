# Open work

1. Stabilize and qualify the composed memory implementation before promotion;
   see [MEMORY.md](MEMORY.md). Further memory optimization is deferred.
   Follow the [promotion review](tests/memory_promotion_review.json): reconcile
   command-suite and retained-memory budget failures, then build a production
   composition without diagnostic-only boot requirements, integrate its matched
   outputs into build/deployment, and qualify that release candidate across
   HIGH/LOW and pre-386 fallback before enabling it by default.
2. Implement retail-compatible DriveSpace, including compressed-volume support
   throughout the system. An explicit extended format may follow.
3. Treat QBASIC/EDIT, AccessDOS, the Microsoft Network Client, and additional
   DOS 6 locale packs as independent epics.

[DOS622_GAPS.md](DOS622_GAPS.md) defines product scope and non-goals;
[DOS5_GAPS.md](DOS5_GAPS.md) records inherited compatibility limits.
[Windows 95 acceptance](tests/WINDOWS95-SETUP.md) describes the external-media
checks and their remaining validation scope.

Use the local release gates in [ARCHITECTURE.md](ARCHITECTURE.md).
