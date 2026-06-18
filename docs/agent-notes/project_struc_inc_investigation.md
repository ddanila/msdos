---
name: struc-inc-rewrite-followup
description: "STRUC.INC `&` substitution failure — discovered the simple patterns work, narrowing in progress. Investigation kit for a follow-up focused session."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8bd8f8ac-1776-4345-b429-e310157d3963
---

## Status

WASM rejects something specific in STRUC.INC's macro chain that produces
~106 E032 errors across ~16 ASM files. **The simple patterns `j&c $l&l`
and `%$ll&l` work in isolation** — proven with reproducers below. So the
failure is in a deeper combination — possibly state interaction with
WASM's macro expansion timing.

Once the surgical fix lands, ~16 files cascade-clean: ANSI, GRCOLPRT,
GRCTRL (mostly), GRLOAD2, IOCTL (DEV/ANSI), MAIN, MODECP, MODEPRIN,
PARSER, ROUTINES, SCN_PARM, SELECT0/2/3/5/8 + maybe DEV/DISPLAY/DISPLAY.

## Failing chain (May 28 build)

```
ANSI.ASM(930) DEV/ANSI
  → STRUC.INC(409) $TopTest         (.IF body)
    → STRUC.INC(379) $Test           ($CondJump dispatcher)
      → STRUC.INC(336) $CondJump      (build jcc to short-circuit)
        → STRUC.INC(243) $CondJump2  (decide near vs short)
          → STRUC.INC(252) jn&c $l&l ← ERROR E032 here
```

Same chain for the other 15 STRUC-blocked files (different caller lines).

## Working reproducers (DO NOT break)

These all assemble cleanly with `wasm -zcm=masm`:

```asm
;; Plain j&c label expansion in MACRO param
TestJ MACRO l, c
        j&c $l&l
ENDM
TestJ 42, e   ; -> je $l42 (works if $l42 defined)
```

```asm
;; %$ll&l double-substitution + forward refs
$ll1 = 42
$Label MACRO n
        $l&n:
ENDM
$CondJ MACRO n,c
        j&c $l&n
ENDM
$DoIt MACRO l,c
        $CondJ %$ll&l,c     ; %$ll&l expands to %$ll1 → 42, then $CondJ 42,c
ENDM
$DoIt 1, e   ; works
```

```asm
;; Forward reference (label defined AFTER use)
TestJ MACRO l, c
        j&c $l&l
ENDM
TestJ 42, e
$l42:        ; works -- forward ref OK
```

## Failing reproducer (close but not exact)

```asm
;; Closer to STRUC.INC's actual flow but with errors of a different type (E031)
$Short EQU 1
$Dist  EQU 1
CondJ2 MACRO l,tf,c,_d
        if $Dist eq $Short
            ifb <c>
                jmp short $l&l
            else
                ifidn <tf>,<f>
                    jn&c $l&l
                else
                    j&c $l&l
                endif
            endif
        endif
ENDM
CondJ2 42,t,e,_   ; -> E031 "Only SHORT displacement allowed" — close but different error class
```

## Investigation kit for next session

1. **First narrow the failure**: copy STRUC.INC L246-L290 ($CondJump2) into a standalone test, feed it the exact arg values it sees during ANSI.ASM(930) call. Need to instrument STRUC.INC to dump `l/tf/c/$Dist/$AndOr` at the failure point — add `%out` statements (which preprocess-wasm strips, so use a different mechanism, like emitting `db 'tag=value'`).

2. **Likely culprits to investigate**:
   - `%$ll&l` expansion at the `$CondJump2 %$ll&l,tf,c,_` call site (line 243 of STRUC.INC). The `%` evaluation when `$ll&l` is itself a constructed name may double-expand or evaluate before construction.
   - The `_d: WASM trailing-comma guard` parameter — added by an earlier session to dodge a different trailing-comma bug. Could be interacting.
   - `$Dist eq $Short` IF evaluation — if WASM mis-evaluates this, both branches of the nested IFs get parsed and the dead one's `j&c` is what fails.

3. **Surgical fix target**: probably 10-30 lines inside $CondJump/$CondJump2/$BuildJump (lines 230-330 of STRUC.INC). The rest of STRUC.INC (state stack, type tags, etc.) is fine. Focus only on jump emission.

## Files affected (current build, May 28 snapshot)

These files have ONLY STRUC.INC errors — no other source-side issues; they will cascade-clean when the STRUC.INC fix lands:

- DEV/ANSI/ANSI.ASM (2 errors via STRUC.INC L252)
- CMD/GRAPHICS/GRCOLPRT.ASM (2 — L328/L648)
- CMD/GRAPHICS/GRCTRL.ASM (1 — L328 cascade; main GRCTRL fix landed)
- CMD/GRAPHICS/GRLOAD2.ASM (5)
- DEV/ANSI/IOCTL.ASM (2)
- CMD/MODE/MAIN.ASM (3 — L182/L398/L662 via SUBTTL macro chain)
- CMD/MODE/MODECP.ASM, MODEPRIN.ASM (varied STRUC chain)
- CMD/KEYB/PARSER.ASM (1)
- CMD/MODE/MAIN.ASM (3)
- SELECT/ROUTINES.ASM (13 — bulk of $CondJump usage)
- SELECT/SCN_PARM.ASM (3)
- SELECT/SELECT0/2/3/5/8.ASM (varying)
- SELECT/ROUTINE2.ASM (1)

DEV/DISPLAY/DISPLAY.ASM (13 — F-PARSER.INC STRUC instantiation, may overlap)
DEV/DISPLAY/INIT.ASM was unblocked by simplifying DEV/DISPLAY/MACROS.INC JUMP macro.

## When picking this up

Start with: `cat /tmp/struc_repro.asm` — has the closest reproduction. Then do `wasm-masm` on it and instrument what's different from `/tmp/struc_pct.asm` (the working one).
