# Open work

The complete product comparison and unsupported option surfaces are in
[DOS622_GAPS.md](DOS622_GAPS.md). Current priorities are:

1. finish the enhanced DOS 6.22 UNDELETE experience;
2. improve SETUP, upgrade, rollback, recovery media, and component selection;
3. add EGA.SYS and standalone full-screen Help;
4. audit and close application-visible documented and undocumented API gaps;
5. implement retail-compatible DriveSpace, followed optionally by an explicit
   extended format; and
6. audit the Supplemental Disk while keeping QBASIC/EDIT as a separate epic.

MSBACKUP, MSAV, VSAFE, DOSSHELL, and Task Swapper are deliberate non-goals.

For every change, keep source-derived manifests complete and add focused
success, failure, and state-transition contracts. Automatic CI remains paused;
use local tests and the emulator roles in [EMULATION.md](EMULATION.md).

Toolchain maintenance should update one pinned fork at a time and pass the
applicable reproducibility and runtime gates. Remove a build adapter only after
its replacement provides equivalent behavior.

Commercial DOS binaries and derived content must not be committed. Genuine
media may be used only as an external clean-room oracle.
