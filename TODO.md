# Open work

The complete product comparison and unsupported option surfaces are in
[DOS622_GAPS.md](DOS622_GAPS.md). Current priorities are:

1. implement Stage 4 data protection: MSBACKUP and the enhanced DOS 6.22
   UNDELETE experience;
2. decide explicitly whether obsolete MSAV/VSAFE compatibility is worth its
   maintenance cost;
3. improve the 6.22 SETUP, upgrade, recovery-media, and Help experience; and
4. plan DriveSpace and QBASIC/EDIT only as separate product-scale epics.

For every change, keep source-derived manifests complete and add focused
success, failure, and state-transition contracts. Automatic CI remains paused;
use local tests and the emulator roles in [EMULATION.md](EMULATION.md).

Toolchain maintenance should update one pinned fork at a time and pass the
applicable reproducibility and runtime gates. Remove a build adapter only after
its replacement provides equivalent behavior.

Commercial DOS binaries and derived content must not be committed. Genuine
media may be used only as an external clean-room oracle.
