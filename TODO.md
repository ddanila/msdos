# Open work

## DOS 5 compatibility

- Implement the persistent `SETVER` database and utility behavior.
- Audit non-memory DOS 5 kernel differences from black-box contracts.
- Extend FDISK, FORMAT, SYS, and setup/update behavior beyond the inherited
  DOS 4 contracts.
- Decide which additional DOS 5 utilities belong in the distribution and use
  only license-compatible implementations or clean-room observations.
- Broaden third-party, redirector, interrupt, and warm-reboot coverage while
  DOS resides in the HMA.
- Complete the advertised HIMEM/XMS conformance matrix before treating the
  repository driver as a universal replacement for commercial XMS managers.

## Maintenance

- Keep strict coverage manifests complete and add tests for meaningful
  boundaries, failures, and state transitions rather than test counts.
- Evaluate `ddanila/JWasm`, `ddanila/open-watcom-v2`, and `ddanila/kvikdos`
  `custom` revisions one tool family at a time through the full release gate.
- Remove retained build adapters only when the underlying tool supplies
  equivalent behavior and reproducibility plus runtime tests remain green.

Commercial DOS binaries and derived content must not be committed. Reference
media may be used only as an external black-box oracle.
