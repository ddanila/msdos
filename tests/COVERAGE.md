# Behavioral coverage and traceability

The coverage goal is contract coverage, not a misleading source-line percentage
for a mixed 16-bit assembly/C system. Every supported external interface must
eventually have focused positive, negative, boundary, and state-transition
tests on the built system under QEMU.

`int21_coverage.json` is the machine-readable traceability inventory for the
kernel's live INT 21h dispatch table. `test_coverage_manifest.py` parses
`DOS/MS_TABLE.ASM` directly, verifies that the table is exactly `00h` through
`6Ch`, rejects stale calls or missing evidence files, and reports four levels:

- **contract tested**: a focused test asserts the function's documented result;
- **behavior observed**: existing E2E behavior reaches the call, but does not
  isolate its complete contract;
- **justified exclusion**: direct testing is not feasible and the reason is
  recorded;
- **uncovered**: no evidence has been established yet.

Run the inventory check with:

```sh
make test-coverage-manifest
```

The normal `make test` and CI build run this structural check. The stricter
completion gate is:

```sh
python3 tests/test_coverage_manifest.py --require-complete
```

That command intentionally fails until every non-excluded dispatch entry has
focused contract evidence. Existing command-level observation is useful, but it
does not satisfy the final coverage goal by itself.

CI also sets `FAIL_ON_SKIP=1`; an unexpected host-test skip is therefore a
failure rather than being folded into the pass count.
