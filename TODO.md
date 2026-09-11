# Open work

1. Implement retail-compatible DriveSpace, including compressed-volume support
   throughout the system. An explicit extended format may follow.
2. Complete the DWED-based EDIT replacement following
   [its implementation gates](dwed/docs/EDIT-PLAN.md). The source-build
   instructions are in [BUILD.md](dwed/docs/BUILD.md). Remaining work includes
   safe resolution of retained recovery files, UI allocation failure handling,
   measured memory limits, remaining runtime qualification, and promotion into
   the distribution as EDIT.
3. Treat QBASIC, AccessDOS, the Microsoft Network Client, and remaining
   DOS 6 locale packs as independent epics.

[DOS622_GAPS.md](DOS622_GAPS.md) defines product scope and non-goals;
[DOS5_GAPS.md](DOS5_GAPS.md) records inherited compatibility limits.
[Windows 95 acceptance](tests/WINDOWS95-SETUP.md) describes the external-media
checks and their remaining validation scope.

Use the local release gates in [ARCHITECTURE.md](ARCHITECTURE.md).
