# Open work

1. Implement retail-compatible DriveSpace, including compressed-volume support
   throughout the system. An explicit extended format may follow.
2. Implement the optional Baltic / CP775 pack for Estonian, Latvian and
   Lithuanian following [BALTIC.md](BALTIC.md).
3. Correct DOS true-version reporting (`INT 21h AX=3306h`) to include the
   HMA residency flag in DH when DOS is HIGH; `QueryTrueVersion` currently
   returns DX=0.
4. Qualify hard-disk BPBs with non-DOS OEM strings: the historical BIOS falls
   back to guessed geometry for mtools-formatted volumes.
5. Treat QBASIC/EDIT, AccessDOS, the Microsoft Network Client, and remaining
   DOS 6 locale packs as independent epics.

[DOS622_GAPS.md](DOS622_GAPS.md) defines product scope and non-goals;
[DOS5_GAPS.md](DOS5_GAPS.md) records inherited compatibility limits.
[Windows 95 acceptance](tests/WINDOWS95-SETUP.md) describes the external-media
checks and their remaining validation scope.

Use the local release gates in [ARCHITECTURE.md](ARCHITECTURE.md).
