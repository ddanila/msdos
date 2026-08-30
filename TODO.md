# Open work

## DOS 5 compatibility

The canonical feature inventory and recommended order are in
[DOS5_GAPS.md](DOS5_GAPS.md). Keep each implementation backed by a black-box
contract and update the inventory when its gap closes.

## MS-DOS 6.22 compatibility

The staged upgrade plan and complete known delta are in
[DOS622_GAPS.md](DOS622_GAPS.md). Implement stages in order unless a component
is explicitly marked as a separate epic or non-goal.

## Maintenance

- Keep strict coverage manifests complete and add tests for meaningful
  boundaries, failures, and state transitions rather than test counts.
- Evaluate `ddanila/JWasm`, `ddanila/open-watcom-v2`, and `ddanila/kvikdos`
  `custom` revisions one tool family at a time through the full release gate.
- Remove retained build adapters only when the underlying tool supplies
  equivalent behavior and reproducibility plus runtime tests remain green.

Commercial DOS binaries and derived content must not be committed. Reference
media may be used only as an external black-box oracle.
