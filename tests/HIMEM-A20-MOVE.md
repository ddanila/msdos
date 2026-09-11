# A20 preservation during BIOS block moves

The IBM AT BIOS can disable A20 when returning from its protected-mode block
move service. HIMEM previously passed that result through. DWED's buffered
configuration reader uses an XMS cache even when document storage is DOS
memory: its first cache write could therefore make a DOS HIGH kernel
inaccessible before the next file seek.

HIMEM now wraps BIOS block moves and restores the physical entry state without
changing the public XMS enable counters. The hook retains the BIOS carry and
AH result, and returns with the caller's original interrupt-enable state. A
failure to restore the gate becomes a BIOS error instead of a successful move.
This covers both XMS moves using the BIOS backend and direct BIOS callers.

The [XMS specification](https://ps-2.kev009.com/basil.holloway/ALL%20PDF/Microsoft_XMS_3%5B1%5D.0_Specification.pdf)
requires A20 preservation by the move function and by the INT 15h block-move
hook. The checked document loader did not trigger this issue; configuration
loading exposed a memory-manager fault rather than a malformed configuration.

Run the synthetic BIOS regression with an explicitly selected driver:

```sh
python3 tests/test_himem_move_a20_qemu.py --himem out/memory-production/files/HIMEM.SYS
```

The test-only driver sits below HIMEM and is armed after boot. It models a
BIOS that drops A20 and can return a controlled error. The probe checks XMS
data round trips, direct BIOS copies, both physical gate states, BIOS error
results and interrupt-enable preservation. It runs DOS LOW so both A20 states
can be exercised without deliberately making the kernel inaccessible.

The separate packaged EDIT test exercises DOS HIGH with actual IBM AT BIOS
under 86Box. The editor package is unchanged. Generated fingerprints, the
previous-driver negative control, ordinary XMS regression results and the
real-BIOS run are recorded in `himem_a20_move_qualification.json`. These checks
do not constitute physical-hardware or all-editor-command acceptance.
