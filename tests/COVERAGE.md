# Behavioral coverage and traceability

This project measures externally visible contract coverage rather than source
line coverage. A mixed 16-bit assembly/C operating system can execute a line
without proving its API result, failure behavior, state transition, or hardware
interaction. Coverage therefore means that every declared interface is either
exercised by focused runtime evidence or has a source-backed exclusion.

## Enforcement

The normal `make test` target runs every manifest verifier with
`--require-complete`. CI also sets `FAIL_ON_SKIP=1`, so a host test that
unexpectedly skips is a failure. A new source-derived interface, stale manifest
entry, missing evidence file, observation-only entry, or uncovered contract
fails the build.

Current enforced inventory:

| Inventory | Total | Contract tested | Justified exclusions |
| --- | ---: | ---: | ---: |
| INT 21h dispatch entries | 109 | 104 | 5 |
| INT 21h function/error pairs | 110 | 94 | 16 |
| Shipped runtime components | 56 | 56 | 0 |
| SELECT.EXE modes | 2 | 2 | 0 |
| CONFIG.SYS directives | 20 | 20 | 0 |
| COMMAND.COM built-ins and startup switches | 43 | 43 | 0 |
| Standalone utility switch/operator forms | 133 | 133 | 0 |
| Shipped executable interfaces | 41 | 41 | 0 |
| DEBUG commands and EMS subcommands | 24 | 24 | 0 |
| Executable help surfaces | 41 | 37 | 4 no-help interfaces |
| DOS interrupt surfaces | 11 | 11 | 0 |
| Installable-device request surfaces | 140 | 92 | 48 |

The 48 device exclusions are post-failed-INIT requests in XMA drivers and are
runtime-proven unreachable on the supported QEMU machine. Other exclusions
must likewise identify the live source condition that makes a path absent,
disabled, unshipped, or unreachable; historical documentation alone is not
evidence.

## Evidence levels

Manifest entries use these levels where applicable:

- `contract`: a focused test asserts the interface's result or state change;
- `observed`: an end-to-end path reaches the interface but does not isolate its
  contract; strict completion rejects this level;
- `excluded`: direct runtime coverage is not meaningful or reachable and the
  live source reason is recorded;
- `uncovered`: no acceptable evidence exists; strict completion rejects it.

Evidence must name a runnable test file. Verifiers reject missing files and,
for runtime claims, evidence that is not wired into the CI workflow. Tests must
assert behavior rather than merely execute a program successfully.

## Source-derived inventories

### INT 21h dispatch and failures

`int21_coverage.json` is checked by `test_coverage_manifest.py`. The verifier
parses the live dispatch table in `src/DOS/MS_TABLE.ASM`, derives entries `00h`
through `6Ch`, and rejects missing or stale rows.

`int21_error_coverage.json` is checked independently by
`test_int21_error_coverage.py`. It derives every allowed function/error pair
from `I21_MAP_E_TAB`. Successful-call coverage cannot therefore mask missing
failure-path coverage.

### Runtime components, SELECT, and CONFIG.SYS

`runtime_coverage.json` is checked by
`test_runtime_coverage_manifest.py`. The verifier derives shipped COM, EXE, and
SYS components from the build and deployment inventories. It also derives
CONFIG.SYS directives from the kernel's live command table and SELECT.EXE's
two positional modes from its parser definitions.

### COMMAND.COM

`command_coverage.json` is checked by `test_command_coverage.py`. The verifier
derives all 37 live internal commands and six startup switches. Operational
subforms such as COPY `/A`, `/B`, and `/V`, DIR `/P` and `/W`, and DEL/ERASE
`/P` are part of the contract evidence rather than separate inferred commands.

### Standalone utility parsers

`utility_parser_coverage.json` is checked by
`test_utility_parser_coverage.py`. Its extractors cover assembly parser tables,
C switch initialization, FC's code-driven grammar, operator forms such as
ATTRIB `+A` and `-R`, and tool-specific parsers such as FDISK and FLUSH13.
Synonyms are distinct entries when the live parser accepts distinct spellings.

`program_interface_coverage.json`, checked by
`test_program_interface_coverage.py`, accounts for all shipped executables that
do not fit an ordinary slash-switch grammar. It classifies positional,
interactive, stream, keyword, bootstrap, COMMAND.COM, and SELECT.EXE surfaces
exactly once.

### DEBUG and help

`debug_command_coverage.json` is checked by
`test_debug_command_coverage.py`. It derives DEBUG's live command table and its
nested EMS commands; inactive error entries do not satisfy the inventory.

`help_coverage.json` is checked by `test_help_coverage.py`. It cross-checks all
shipped executable interfaces against actual `/?` test calls or an explicit
source-backed classification for interfaces without top-level help.

### DOS interrupts and device requests

`dos_interrupt_coverage.json` is checked by
`test_dos_interrupt_coverage.py`. It covers the interrupt vectors installed by
the built DOS system, including asynchronous behavior where applicable.

`device_request_coverage.json` is checked by
`test_device_request_coverage.py`. The verifier derives command numbers and
handlers from every explicit shipped-driver request table and records forwarding
models used by layered drivers. Reachable ordinary, no-op, unsupported, and
pass-through handlers require runtime contracts.

## Oracle integrity

Coverage evidence must not pass when the claimed deployed artifact is absent.
`oracle_mutation_coverage.json` and `test_oracle_mutation_coverage.py` enforce a
deletion-mutation result for every shipped runtime component.
`audit_oracle_mutation.sh` runs a focused suite against a private floppy copy
with one component removed; the suite must fail. Mutation tests never modify
the canonical deployed image.

Serial batch tests disable command echo before redirecting to the serial device.
`test_batch_oracles.py` derives and enforces this invariant, preventing a marker
embedded in AUTOEXEC.BAT from satisfying its own output assertion.

## Runtime layers

kvikdos is the fast layer for deterministic command behavior that does not
depend on a complete machine. QEMU is required for kernel and hardware
contracts, boot flow, interrupts, filesystems, block devices, drivers, TSRs,
interactive console behavior, and EMM386.

Tests that mutate disks or files use private copies and accept a `FLOPPY_IMAGE`
override where appropriate. This permits parallel execution and supports the
mutation audit without serializing access to `out/floppy.img`.

## Commands

Run all manifest checks as part of the normal suite:

```sh
make test
```

Run an individual inventory while editing it:

```sh
make test-coverage-manifest
make test-int21-error-coverage-manifest
make test-runtime-coverage-manifest
make test-command-coverage-manifest
make test-utility-parser-coverage-manifest
make test-program-interface-coverage-manifest
make test-debug-command-coverage-manifest
make test-help-coverage-manifest
make test-dos-interrupt-coverage-manifest
make test-device-request-coverage-manifest
```

The per-inventory output is the authoritative current count. Update the table
above in the same commit whenever a source-derived total changes.
