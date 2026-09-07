# DOS 5 compatibility limits

This file records inherited DOS 5 limitations. The system targets DOS 6.22;
[DOS622_GAPS.md](DOS622_GAPS.md) owns product scope and separate epics.
The reference manuals are listed in [REFERENCE.md](REFERENCE.md).

Build and distribution inventories identify shipped components. The manifests
under `tests/` describe their tested interfaces; see
[tests/COVERAGE.md](tests/COVERAGE.md). Neither a source file nor a complete
manifest proves every retail behavior or hardware combination.

## Known differences

- EDIT and QBASIC are absent and form a separate epic. EDLIN is available.
- DOSSHELL and Task Swapper are permanent non-goals. EGA.SYS is supported
  independently of them.
- MIRROR's deletion tracker has a larger resident footprint than retail.
- The installer, disk layout, and independently written Help corpus do not
  reproduce retail presentation or manual text.

## Validation limits

- Memory layout changes still need composition and fallback qualification;
  see [MEMORY.md](MEMORY.md).
- CONFIG.SYS limits, ordering and errors, asynchronous callbacks, critical
  errors, sharing, locking, and redirector interactions have focused coverage,
  not exhaustive combinations.
- HIMEM A20 backends, EMM386's Weitek and low page-frame modes, shadow RAM,
  physical controllers, and hardware timing are not exhaustively validated.
- ANSI escape sequences, display/printer adapters and code pages, and custom
  DRIVER.SYS geometries have bounded runtime coverage.
- FDISK has focused multi-disk coverage. Physical storage and removable-media
  combinations remain outside that scope.
- There is no automated differential runner against genuine DOS 5 media or
  maintained physical-hardware lab.

An unverified behavior is an evidence gap, not automatically an implementation
defect. Add a concrete discrepancy here when a source or runtime comparison
establishes it; keep implemented option inventories in code and test manifests.
