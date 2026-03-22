#!/usr/bin/env python3
"""
Post-process MASM message class files (*.CL?) to fix WASM single-pass
forward reference issue: move 'Class_X_MessageCount EQU N' lines to
BEFORE the '$M_CLASS_ID <...>' structure instantiation.
"""
import re
import sys
import os
import glob

def fix_cl_file(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    # Remove %out directives — WASM bug: %out causes OBJ to not be written
    changed_pct = False
    new_lines = []
    for line in lines:
        if re.match(r'^\s*%out\b', line, re.IGNORECASE):
            new_lines.append(';; WASM: %out removed (causes WASM to discard OBJ)\n')
            changed_pct = True
        else:
            new_lines.append(line)
    if changed_pct:
        lines = new_lines

    # Add $M_HAS_xxx = 1 flag after PUBLIC $M_CLS_N / $M_MSGSERV_N lines.
    # WASM: MSGDCL.INC checks IFNDEF $M_HAS_xxx (not the symbol itself) to decide
    # PUBLIC vs EXTRN.  A symbol declared EXTRN fools WASM's IFNDEF into FALSE,
    # so we use a separate flag that is only set when the symbol is *defined* here.
    # First strip any pre-existing HAS flags (idempotent re-run support).
    lines = [l for l in lines if not re.match(r'^\$M_HAS_', l)]
    changed_has = False
    new_lines2 = []
    for line in lines:
        new_lines2.append(line)
        m = re.match(r'^\s+PUBLIC\s+(\$M_CLS_\d+|\$M_MSGSERV_\d+)\s*$', line, re.IGNORECASE)
        if m:
            sym = m.group(1).upper()              # e.g. $M_CLS_3 or $M_MSGSERV_1
            # Drop leading '$M_' to get 'CLS_3' or 'MSGSERV_1'
            root = sym[3:] if sym.startswith('$M_') else sym
            flag = '$M_HAS_' + root             # $M_HAS_CLS_3 or $M_HAS_MSGSERV_1
            # $M_CHECK uses IFNDEF $M_HAS_&parm where parm=$M_CLS_3 -> $M_HAS_$M_CLS_3
            flag2 = '$M_HAS_' + sym             # e.g. $M_HAS_$M_CLS_3
            new_lines2.append(f'{flag} = 1\t\t\t\t;; WASM: real LABEL defined here (not just EXTRN)\n')
            new_lines2.append(f'{flag2} = 1\t\t\t\t;; WASM: $M_HAS_&parm form for $M_CHECK macro\n')
            changed_has = True
    if changed_has:
        lines = new_lines2

    # Find all 'Class_X_MessageCount EQU N' lines
    equ_indices = [i for i, l in enumerate(lines) if re.match(r'^\s*Class_\w+MessageCount\s+EQU\s+\d+', l, re.IGNORECASE)]
    # Find '$M_CLASS_ID <...' line (structure instantiation)
    struct_idx = next((i for i, l in enumerate(lines) if '$M_CLASS_ID' in l and '<' in l), None)

    if not equ_indices or struct_idx is None:
        if changed_pct or changed_has:
            with open(filepath, 'w') as f:
                f.writelines(lines)
            print(f"Fixed: {filepath}")
        return changed_pct or changed_has

    # Check if any EQU comes after the struct instantiation
    late_equs = [i for i in equ_indices if i > struct_idx]
    if not late_equs:
        if changed_pct or changed_has:
            with open(filepath, 'w') as f:
                f.writelines(lines)
            print(f"Fixed: {filepath}")
        return changed_pct or changed_has

    changed = False
    for equ_idx in sorted(late_equs, reverse=True):
        equ_line = lines.pop(equ_idx)
        # Insert before the struct line (adjust for removed lines)
        insert_pos = struct_idx
        lines.insert(insert_pos, equ_line)
        changed = True

    if changed or changed_pct or changed_has:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        print(f"Fixed: {filepath}")
    return changed or changed_pct or changed_has


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix_cl_forward_refs.py <dir_or_file> [...]")
        sys.exit(1)

    for pattern in sys.argv[1:]:
        for filepath in glob.glob(pattern) or [pattern]:
            if os.path.isfile(filepath):
                fix_cl_file(filepath)
            elif os.path.isdir(filepath):
                for ext in ['CL1', 'CL2', 'CL3', 'CL4', 'CLA', 'CLB', 'CLC', 'CLD', 'CLE', 'CLF']:
                    for f in glob.glob(os.path.join(filepath, f'*.{ext}')):
                        fix_cl_file(f)
