#!/usr/bin/env python3
"""Observe EMM initialization boundaries in a privately linked trace build."""
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

import capture_drdos_memory as capture
from emm_loader_rebase import include as rebase_include, manifest as rebase_manifest
from report_himem_residency import bootstrap_layout, parse_symbols, PROCEDURE_RE


def strip_capacity_records(data, *, handles=None, altregs=None):
    """Consume public-API witnesses in reverse batch order; keep phase bytes."""
    for tag, expected in ((b"AC", altregs), (b"HC", handles)):
        if expected is not None:
            if not data.endswith(tag + struct.pack("<H", expected)):
                raise ValueError(f"{tag.decode()} capacity/exhaustion/reuse probe failed")
            data = data[:-4]
    return data


def parse_bootstrap_layout(data):
    if len(data) != 14:
        raise ValueError("missing bootstrap layout receipt")
    tag, segment, permanent, records, count, end, entry = struct.unpack("<2s6H", data)
    if (tag != b"XL" or not segment or not 0 < permanent < records < end
            or permanent % 16 or not 1 <= count <= 128
            or end != ((records + count * 5 + 15) & ~15)
            or segment + end // 16 > 0xa000 or entry >= permanent):
        raise ValueError("invalid bootstrap layout receipt")
    return dict(segment=segment, permanent_bytes=permanent, records_offset=records,
                handles=count, boot_end=end, entry_offset=entry,
                retained_bootstrap_bytes=end-permanent, released_bytes=0)


def parse_post_boot(data, expected):
    if len(data) != 10:
        raise ValueError("missing post-boot allocation witness")
    tag, psp, largest, himem_size, emm_size = struct.unpack("<2s4H", data)
    if (tag != b"MC" or not 0 < psp < 0xa000 or not largest
            or psp + largest >= 0xa000 or not 0 < himem_size < 0xa000
            or not 0 <= emm_size < 0xa000 or bool(emm_size) != bool(expected)):
        raise ValueError("invalid post-boot allocation witness")
    return dict(psp_segment=psp, largest_bytes=largest * 16,
                himem_bytes=himem_size * 16, emm_bytes=emm_size * 16)


def parse_umb_receipt(data, *, mode, rejected):
    if data not in (b"UC\0", b"UC\1"):
        raise ValueError("missing UMB ownership/coalescing witness")
    synthetic = bool(data[-1])
    if synthetic != (mode != "RAM" or rejected):
        raise ValueError("UMB witness used an unexpected registration owner")
    return synthetic


def parse_private_umb_receipt(data):
    if data != b"UP" + struct.pack("<3H", 1, 1, 0):
        raise ValueError("installed private UMB lifecycle witness failed")
    return dict(active=True, imports=1, records=0, public_handoff=False)


def parse_umb_handoff(data, *, mode):
    if len(data) != 8:
        raise ValueError("missing public UMB handoff witness")
    tag, active, imports, records = struct.unpack("<2s3H", data)
    if (tag != b"UH" or active != 1 or imports != 1 or records > 32
            or bool(records) != (mode == "RAM")):
        raise ValueError("invalid public UMB handoff witness")
    return dict(active=True, imports=1, records=records, public_handoff=True,
                retired_low_poisoned=True, backing_released=False)


def parse_live_umb_import(data, *, mode):
    if len(data) != 8:
        raise ValueError("missing live UMB import witness")
    tag, first, second, blocks = struct.unpack("<2s3H", data)
    if (tag != b"UL" or blocks != 2 or first >= second
            or mode not in ("ON", "OFF", "AUTO", "RAM")
            or not 0xa000 <= first < 0xf000 or not 0xa000 <= second < 0xf000):
        raise ValueError("invalid live UMB import witness")
    return dict(segments=[first, second], paragraphs_each=1, released_through_high_owner=True,
                backing_accessed=mode == "RAM", payload_verified=mode == "RAM")


def parse_common_binding(data):
    if len(data) != 8:
        raise ValueError("missing common binding witness")
    tag, offset, segment, refused = struct.unpack("<2s3H", data)
    if tag != b"CB" or not offset or not 0 < segment < 0xa000 or refused != 1:
        raise ValueError("invalid common binding witness")
    return dict(entry=f"{segment:04X}:{offset:04X}", discovery_disabled=True,
                revoked_call_refused=True, backing_released=False)


def parse_umb_service_receipt(data, *, failure, common_frame=False):
    if len(data) != 10:
        raise ValueError("missing sequenced UMB service witness")
    if failure == "unknown":
        tag, state, sequence, refused = struct.unpack("<2sHIH", data)
        if tag != b"UX" or state != 3 or not sequence or refused != (6 if common_frame else 3):
            raise ValueError("invalid pending UMB service witness")
        return dict(sequence=sequence, pending=True, later_operations_refused=refused,
                    replayed=False, pending_packet_preserved=True)
    tag, sequence, recovered, not_executed = struct.unpack("<2sI2H", data)
    if (tag != b"UR" or not sequence or failure not in (None, "before", "after")
            or recovered != int(failure == "after") or not_executed != int(failure == "before")):
        raise ValueError("invalid sequenced UMB service witness")
    return dict(sequence=sequence, recovered=recovered, not_executed=not_executed,
                replayed=False, pending=False)


def parse_trace(data, *, split=False, rejected=False, activation_stack=False,
                lifecycle=False, loader=False, rebase=False, table_layout=False,
                bootstrap_owner=False, authoritative_owner=False, rebase_rejected=False,
                reclaim_bootstrap=False):
    if reclaim_bootstrap and not (rebase and authoritative_owner and loader):
        raise ValueError("downward move requires loader, rebasing and authoritative layout")
    if rebase_rejected and not (rebase and rejected):
        raise ValueError("rejected move requires rebasing and cancellation")
    if authoritative_owner and not bootstrap_owner:
        raise ValueError("authoritative publication requires the live owner witness")
    owner = None
    if bootstrap_owner:
        suffix = b"LD" if loader else b""
        end = len(data) - len(suffix)
        if end < 10 or (suffix and not data.endswith(suffix)):
            raise ValueError("missing bootstrap XMS owner witness")
        tag, handle, physical, size = struct.unpack("<2sHIH", data[end-10:end])
        if tag != b"XO" or not handle or physical < 0x100000 or size != 1:
            raise ValueError("invalid bootstrap XMS owner witness")
        owner = dict(handle=handle, physical=physical, size_kib=size)
        data = data[:end-10] + suffix
        if authoritative_owner:
            end = len(data) - len(suffix)
            owner["layout"] = parse_bootstrap_layout(data[end-14:end])
            data = data[:end-14] + suffix
        if authoritative_owner and not rejected:
            end = len(data) - len(suffix)
            if end < 6:
                raise ValueError("missing installed high allocator publication")
            tag, base = struct.unpack("<2sI", data[end-6:end])
            if tag != b"XA" or base < 0x100000:
                raise ValueError("missing installed high allocator publication")
            owner["high_code_base"] = base
            data = data[:end-6] + suffix
        owner["high_committed"] = bool(authoritative_owner and not rejected)
    moved = None
    if rebase_rejected:
        if data[26:28] != b"RF":
            raise ValueError("missing prepared-image move rejection")
        data = data[:26] + data[28:]
    elif rebase:
        if len(data) < 34:
            raise ValueError("missing prepared-image move")
        tag, old, new, paragraphs = struct.unpack_from("<2s3H", data, 26)
        delta = -(owner["layout"]["retained_bootstrap_bytes"] // 16) if reclaim_bootstrap else 32
        if tag != b"RB" or new != old + delta or paragraphs <= abs(delta):
            raise ValueError("invalid prepared-image move")
        moved = dict(old=old, new=new, paragraphs=paragraphs)
        data = data[:26] + data[34:]
    order = ([1, 9, 10] if rejected else
             [1, 9, *range(2, 9)] if split else list(range(1, 9)))
    if activation_stack:
        order = order[:2] + [12] + order[2:] + [13]
    if lifecycle:
        order.append(15)
    if loader:
        if not data.endswith(b"LD"):
            raise ValueError("missing SYSINIT callback completion")
        data = data[:-2]
        order.insert(2, 17)
    layout = None
    if table_layout:
        position = (order.index(6) + 1) * 13
        if len(data) < position + 12:
            raise ValueError("missing table layout")
        tag, physical, size, end, high = struct.unpack_from("<2sI3H", data, position)
        if (tag != b"HT" or high not in (0, 1) or not size or not end
                or bool(physical >= 0x100000) != bool(high)):
            raise ValueError("invalid table owner layout")
        layout = dict(physical=physical, bytes=size, end=end, high=high)
        data = data[:position] + data[position + 12:]
    if len(data) != len(order) * 13:
        raise ValueError("incomplete or unexpected initialization trace")
    result = []
    for index, expected in enumerate(order):
        tag, stage, msw, ip15, cs15, ip67, cs67 = struct.unpack_from(
            "<2sB5H", data, index * 13)
        if tag != b"IP" or stage != expected:
            raise ValueError("invalid initialization phase order")
        result.append(dict(stage=stage, pe=msw & 1, msw=msw,
                           int15=f"{cs15:04X}:{ip15:04X}",
                           int67=f"{cs67:04X}:{ip67:04X}"))
    if moved:
        result[2]["move"] = moved
    if layout:
        result[order.index(6)]["tables"] = layout
    if owner:
        result[-1]["bootstrap_owner"] = owner
    return result


def check_phases(rows, mode, *, split=False, rejected=False, activation_stack=False,
                 lifecycle=False, loader=False, rebase=False):
    if rebase and not rejected:
        for vector in ("int15", "int67"):
            if int(rows[-1][vector].split(":")[0], 16) != rows[2]["move"]["new"]:
                raise ValueError("activated entry does not follow the moved image")
    if loader:
        if any(rows[2][key] != rows[1][key] for key in ("pe", "int15", "int67")):
            raise ValueError("loader resume changed prepared machine state")
        rows = rows[:2] + rows[3:]
    if lifecycle:
        if any(rows[-1][key] != rows[-2][key] for key in ("pe", "int15", "int67")):
            raise ValueError("rejected lifecycle calls changed terminal machine state")
        rows = rows[:-1]
    if activation_stack:
        for first, second in ((rows[1], rows[2]), (rows[-2], rows[-1])):
            if any(first[key] != second[key] for key in ("pe", "int15", "int67")):
                raise ValueError("activation stack boundary changed machine state")
        rows = rows[:2] + rows[3:-1]
    if split or rejected:
        if rows[1]["pe"] or any(rows[1][key] != rows[0][key]
                                for key in ("int15", "int67")):
            raise ValueError("preparation changed CPU or public vectors")
        if rejected:
            if rows[2]["pe"] or any(rows[2][key] != rows[0][key]
                                    for key in ("int15", "int67")):
                raise ValueError("rejected preparation did not restore state")
            return
        rows = rows[:1] + rows[2:]
    final_pe = 1 if mode in ("ON", "RAM") else 0
    if [row["pe"] for row in rows] != [0] * 5 + [1, final_pe, final_pe]:
        raise ValueError("unexpected CPU activation boundary")
    for vector in ("int15", "int67"):
        if any(row[vector] != rows[0][vector] for row in rows[:7]):
            raise ValueError("interrupt entry published before final phase")
        if rows[7][vector] == rows[0][vector]:
            raise ValueError("final interrupt entry was not published")


def build_loader(work, *, rejected=False, bad_version=False, rebase=False, bad_rebase=False,
                 stage_bootstrap=False, reclaim_bootstrap=False):
    """Private BIOS with linked-end DOS staging for the larger SYSINIT witness."""
    bios = work / "BIOS"
    shutil.copytree(capture.ROOT / "src/BIOS", bios)
    original = capture.sha256(capture.ROOT / "src/BIOS/IO.SYS")
    options = "-DBIOS_DEFER_PROVIDER"
    if rebase:
        options += " -DPROVIDER_REBASE"
        if stage_bootstrap:
            options += " -DBIOS_STAGE_PROVIDER"
        if reclaim_bootstrap:
            options += " -DBIOS_PROVIDER_DOWN"
        (bios / "PROVIDERFIXUPS.INC").write_text(rebase_include(
            (work / "MEMM/MEMM/EMM386.EXE").read_bytes(), bad_control=bad_rebase))
    if rejected:
        options += " -DBIOS_PROVIDER_CANCEL"
    if bad_version:
        options += " -DBIOS_PROVIDER_BAD_VERSION"
    for defines in ("", options):
        if defines:
            # The normal MSINIT object reserves a fixed SYSIZE for SYSINIT.
            # Instrumentation can exceed it before the first provider call.
            subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                            "-I. -I../INC -DBIOS_DYNAMIC_STAGING",
                            "MSINIT.ASM,MSINIT.OBJ;"],
                           cwd=bios, check=True, stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                        f"-I. -I../INC {defines}", "SYSCONF.ASM,SYSCONF.OBJ;"],
                       cwd=bios, check=True, stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/wlink"), "@MSBIO.LNK"],
                       cwd=bios, check=True, stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/exe2bin"), "MSBIO.EXE", "MSBIO.BIN"],
                       cwd=bios, input=b"70\n", check=True, stdout=subprocess.DEVNULL)
        (bios / "IO.SYS").write_bytes((bios / "MSLOAD.COM").read_bytes()
                                     + (bios / "MSBIO.BIN").read_bytes())
        if not defines and capture.sha256(bios / "IO.SYS") != original:
            raise RuntimeError("normal BIOS reconstruction differs; rebuild bios first")
    return bios / "IO.SYS", original


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--split-prepare", action="store_true")
    parser.add_argument("--bootstrap-owner", action="store_true",
                        help="preserve a locked, filled XMS block across the loader transaction")
    parser.add_argument("--authoritative-owner", action="store_true",
                        help="activate the paired high allocator through the loader callback")
    parser.add_argument("--bad-owner-receipt", choices=("before", "after"),
                        help="lie about commit state before or after handoff; must fail")
    parser.add_argument("--bad-bootstrap-layout", action="store_true",
                        help="report a false aligned low boundary; linked reconciliation must fail")
    parser.add_argument("--stage-bootstrap", action="store_true",
                        help="stage the allocator in owned LAST scratch and poison its original tail")
    parser.add_argument("--reclaim-bootstrap", action="store_true",
                        help="move the prepared provider down into the adjacent bootstrap tail")
    parser.add_argument("--umb-coalesce", action="store_true",
                        help="check public UMB/peer lifetime and guard the next resident owner")
    parser.add_argument("--umb-owner", action="store_true",
                        help="exercise the installed high XUMB publication and services")
    parser.add_argument("--umb-handoff", action="store_true",
                        help="route public and peer UMB calls through one high owner")
    parser.add_argument("--umb-service-receipts", action="store_true",
                        help="sequence UMB services and recover results without replay")
    parser.add_argument("--common-xms-entry", action="store_true",
                        help="route high handle, resolved-copy and UMB adapters through one core")
    parser.add_argument("--bad-common-xms-entry", choices=("handle", "copy", "umb"),
                        help="negative control: reject one service family in the common core")
    parser.add_argument("--bad-common-move-low", action="store_true",
                        help="negative control: use the retired low Move resolver")
    parser.add_argument("--bad-common-binding", choices=("rediscover", "guard"),
                        help="negative control: rediscover a bound provider or ignore revocation")
    parser.add_argument("--bad-common-frame", action="store_true",
                        help="negative control: allocate through the retired handle packet")
    parser.add_argument("--umb-sequence-wrap", action="store_true",
                        help="seed both confirmed sequence counters near 32-bit wrap")
    parser.add_argument("--umb-service-reply", choices=("before", "after", "unknown"),
                        help="drop one allocation reply before execution or after completion")
    parser.add_argument("--bad-umb-result-freeze", action="store_true",
                        help="negative control: fail to freeze an unknowable service result")
    parser.add_argument("--umb-live-import", action="store_true",
                        help="preserve public UMB allocations made before ownership handoff")
    parser.add_argument("--bad-umb-import-bits", action="store_true",
                        help="negative control: clear live allocation bits during import")
    parser.add_argument("--umb-lost-import-reply", action="store_true",
                        help="require receipt recovery after a committed import loses its reply")
    parser.add_argument("--umb-refused-import", action="store_true",
                        help="require confirmed non-commit before unfreezing the low owner")
    parser.add_argument("--bad-umb-low-owner", action="store_true",
                        help="negative control: use retired low UMB state after commitment")
    parser.add_argument("--bad-umb-route", action="store_true",
                        help="negative control: omit inactive-mode XUMB routing; must fail")
    parser.add_argument("--bad-umb-bound", action="store_true",
                        help="negative control: let UMB coalescing cross into the next owner")
    parser.add_argument("--skip-stage-retarget", action="store_true",
                        help="negative control: move the stage but leave its private root stale")
    parser.add_argument("--xms-handles", type=int, choices=(8, 32, 128), default=32,
                        help="HIMEM handle capacity, distinct from EMS --handles")
    parser.add_argument("--dos-high", action="store_true",
                        help="test authoritative handoff with current DOS high and its cached entry")
    parser.add_argument("--bad-bootstrap-owner", action="store_true",
                        help="corrupt the last readback byte; this run must fail")
    parser.add_argument("--table-layout", action="store_true",
                        help="report the complete table owner and final driver break")
    parser.add_argument("--high-tables", action="store_true",
                        help="relocate the complete EMM table owner into locked extended memory")
    parser.add_argument("--handles", type=int, choices=range(2, 256), metavar="2..255",
                        help="request an explicit EMS handle capacity")
    parser.add_argument("--altregs", type=int, choices=range(0, 255), metavar="0..254",
                        help="request an explicit alternate-register-set capacity")
    parser.add_argument("--switch-altregs", action="store_true",
                        help="also select each set and restore set zero; requires --altregs")
    parser.add_argument("--loader", action="store_true",
                        help="return from INIT and resume through a private SYSINIT callback")
    parser.add_argument("--loader-rebase", action="store_true",
                        help="move the prepared image upward 512 bytes and poison its old entry area")
    parser.add_argument("--loader-bad-rebase", action="store_true",
                        help="corrupt a pinned fixup precondition; require rejection, not movement")
    parser.add_argument("--loader-bad-version", action="store_true",
                        help="advertise an unsupported version; require synchronous fallback")
    parser.add_argument("--lifecycle", action="store_true",
                        help="exercise invalid calls before prepare, after prepare and after completion")
    parser.add_argument("--bad-lifecycle-control", action="store_true",
                        help="invalidate the lifecycle witness; this run must fail")
    parser.add_argument("--activation-stack", action="store_true",
                        help="resume on a separate guarded stack with BP cleared")
    parser.add_argument("--bad-stack-control", action="store_true",
                        help="invalidate the stack guard; this run must fail")
    parser.add_argument("--poison-request", action="store_true",
                        help="erase saved INIT request registers during activation")
    parser.add_argument("--reject-prepared", action="store_true")
    parser.add_argument("--bad-pool-control", action="store_true",
                        help="corrupt the cleanup witness; this run must fail")
    args = parser.parse_args()
    if args.bad_common_xms_entry or args.bad_common_move_low or args.bad_common_binding or args.bad_common_frame:
        args.common_xms_entry = True
    if args.common_xms_entry:
        args.umb_service_receipts = True
    if args.bad_umb_result_freeze:
        args.umb_service_reply = "unknown"
    if args.umb_service_reply or args.umb_sequence_wrap:
        args.umb_service_receipts = True
    if args.umb_service_receipts:
        args.umb_handoff = True
    if args.bad_umb_import_bits:
        args.umb_live_import = True
    if args.umb_live_import:
        args.umb_handoff = True
    if args.umb_lost_import_reply and args.umb_refused_import:
        parser.error("pre-commit refusal and lost committed reply are separate controls")
    if args.umb_lost_import_reply or args.umb_refused_import or args.bad_umb_low_owner:
        args.umb_handoff = True
    if args.umb_handoff:
        if args.umb_owner or args.bad_umb_route:
            parser.error("public handoff and independent private owner probes are separate")
        args.umb_coalesce = True
    if args.umb_service_reply == "unknown" and args.umb_live_import:
        parser.error("pending-service probe uses the free-owner baseline")
    if args.bad_umb_route:
        args.umb_owner = True
    if args.umb_owner:
        args.authoritative_owner = True
    if args.bad_umb_bound:
        args.umb_coalesce = True
    if args.umb_coalesce:
        args.authoritative_owner = True
    if args.reclaim_bootstrap:
        args.stage_bootstrap = True
        args.loader_rebase = True
    if args.skip_stage_retarget:
        args.stage_bootstrap = True
        args.loader_rebase = True
    if args.stage_bootstrap:
        args.authoritative_owner = True
        if args.loader_bad_version:
            parser.error("staging requires the negotiated loader callback")
    if args.bad_bootstrap_layout:
        args.authoritative_owner = True
    if args.bad_owner_receipt:
        args.authoritative_owner = True
        if args.reject_prepared or args.loader_bad_rebase or args.loader_bad_version:
            parser.error("receipt negative control requires an installed provider")
    if args.dos_high and not args.authoritative_owner:
        parser.error("--dos-high requires --authoritative-owner")
    if args.authoritative_owner:
        args.bootstrap_owner = True
    if args.bad_bootstrap_owner:
        args.bootstrap_owner = True
    if args.bootstrap_owner:
        args.loader = True
    if args.high_tables:
        args.table_layout = True
    if args.table_layout and any((args.reject_prepared, args.bad_pool_control,
                                 args.loader_bad_rebase)):
        parser.error("table layout requires activation")
    if args.loader_bad_rebase:
        args.loader_rebase = True
        args.reject_prepared = True
    if args.loader_rebase:
        args.loader = True
        if args.loader_bad_version:
            parser.error("rebase and version-fallback controls are separate")
    if args.loader_bad_version:
        args.loader = True
    if args.loader:
        args.split_prepare = True
        if any((args.lifecycle, args.bad_lifecycle_control, args.activation_stack,
                args.bad_stack_control, args.poison_request, args.bad_pool_control)):
            parser.error("--loader uses SYSINIT's stack; do not combine adapter-only witnesses")
        if args.loader_bad_version and args.reject_prepared:
            parser.error("version fallback control requires the normal activation path")
    if args.bad_lifecycle_control:
        args.lifecycle = True
    if args.lifecycle:
        args.split_prepare = True
    if args.bad_pool_control:
        args.reject_prepared = True
    if args.reject_prepared:
        args.split_prepare = True
    if args.poison_request:
        args.split_prepare = True
    if args.bad_stack_control:
        args.activation_stack = True
    if args.activation_stack:
        args.split_prepare = True
    if args.switch_altregs and args.altregs is None:
        parser.error("--switch-altregs requires --altregs")
    if (args.altregs is not None or args.handles is not None) and args.reject_prepared:
        parser.error("capacity probes require an installed provider")
    if ((args.umb_owner and args.reject_prepared)
            or ((args.umb_owner or args.umb_handoff) and args.loader_bad_version)):
        parser.error("private UMB owner requires an installed authoritative provider")
    if args.reject_prepared and (args.umb_lost_import_reply or args.umb_refused_import
                                or args.bad_umb_low_owner or args.umb_live_import or args.umb_service_receipts):
        parser.error("UMB handoff fault controls require an installed provider")
    capture.require_tools()
    if args.authoritative_owner:
        subprocess.run(["make", "dos", "cmd_command"], cwd=capture.ROOT, check=True,
                       stdout=subprocess.DEVNULL)
    image_hash = capture.sha256(args.image)
    work = Path(tempfile.mkdtemp(prefix="emm-init-phases-", dir=capture.ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    shutil.copytree(capture.ROOT / "src/MEMM", work / "MEMM")
    if args.loader:
        shutil.copytree(capture.ROOT / "src/INC", work / "INC")
    if args.authoritative_owner:
        shutil.copytree(capture.ROOT / "src/DEV/HIMEM", work / "DEV/HIMEM")
    build = work / "MEMM/MEMM"
    original = capture.sha256(capture.ROOT / "src/MEMM/MEMM/EMM386.EXE")
    trace_defines = "-DEMM_INIT_PHASE_TRACE"
    if args.common_xms_entry:
        trace_defines += " -DEMM_COMMON_XMS_TEST"
    if args.bad_common_binding == "guard":
        trace_defines += " -DEMM_COMMON_BOUND_UNGUARDED"
    if args.bad_common_xms_entry:
        trace_defines += " -DEMM_COMMON_XMS_REJECT_" + args.bad_common_xms_entry.upper()
    if args.bootstrap_owner:
        trace_defines += " -DEMM_BOOTSTRAP_OWNER_TEST"
    if args.umb_owner or args.umb_handoff:
        trace_defines += " -DEMM_UMB_OWNER_TEST"
    if args.bad_umb_route:
        trace_defines += " -DEMM_UMB_OWNER_BAD_ROUTE"
    if args.umb_lost_import_reply:
        trace_defines += " -DEMM_UMB_OWNER_LOST_IMPORT_REPLY"
    if args.umb_refused_import:
        trace_defines += " -DEMM_UMB_OWNER_REFUSE_FIRST_IMPORT"
    if args.bad_umb_import_bits:
        trace_defines += " -DEMM_UMB_OWNER_CLEAR_ALLOCATED_TEST"
    if args.umb_service_receipts:
        trace_defines += " -DEMM_UMB_RESULTS_TEST"
    if args.umb_sequence_wrap:
        trace_defines += " -DEMM_UMB_SEQUENCE_WRAP_TEST"
    if args.umb_service_reply:
        trace_defines += {"before": " -DEMM_UMB_RESULT_DROP_BEFORE",
                          "after": " -DEMM_UMB_RESULT_DROP_AFTER",
                          "unknown": " -DEMM_UMB_RESULT_UNKNOWN"}[args.umb_service_reply]
    if args.authoritative_owner:
        trace_defines += (" -DEMM_XMS_COPY_TEST -DEMM_XMS_OWNER_TEST"
                          " -DEMM_AUTHORITATIVE_OWNER_TEST -DEMM_XMS_OWNER_TRACE")
        trace_defines += f" -DEMM_BOOTSTRAP_XMS_HANDLES={args.xms_handles}"
    if args.dos_high:
        trace_defines += " -DEMM_BOOTSTRAP_EXPECT_HMA"
    if args.stage_bootstrap:
        trace_defines += " -DEMM_BOOTSTRAP_STAGE_TEST"
    if args.skip_stage_retarget:
        trace_defines += " -DEMM_BOOTSTRAP_SKIP_RETARGET"
    if args.bad_owner_receipt:
        trace_defines += (" -DEMM_XMS_OWNER_BAD_RECEIPT" if args.bad_owner_receipt == "before"
                          else " -DEMM_XMS_OWNER_BAD_RECEIPT_ACTIVE")
    if args.bad_bootstrap_owner:
        trace_defines += " -DEMM_BOOTSTRAP_OWNER_BAD"
    if args.table_layout:
        trace_defines += " -DEMM_TABLE_LAYOUT_TRACE"
    if args.high_tables:
        trace_defines += " -DEMM_HIGH_TABLES"
    if args.split_prepare:
        trace_defines += " -DEMM_SPLIT_PREPARE"
    if args.loader:
        trace_defines += " -DEMM_DEFER_PROVIDER"
    if args.loader_rebase:
        trace_defines += " -DPROVIDER_REBASE"
    if args.lifecycle:
        trace_defines += " -DEMM_PROVIDER_LIFECYCLE"
    if args.bad_lifecycle_control:
        trace_defines += " -DEMM_PROVIDER_BAD_LIFECYCLE"
    if args.poison_request:
        trace_defines += " -DEMM_POISON_INIT_REQUEST"
    if args.activation_stack:
        trace_defines += " -DEMM_ACTIVATION_STACK"
    if args.bad_stack_control:
        trace_defines += " -DEMM_ACTIVATION_BAD_STACK"
    if args.reject_prepared:
        trace_defines += " -DEMM_REJECT_PREPARED"
    if args.bad_pool_control:
        trace_defines += " -DEMM_PREPARE_BAD_POOL"
    for define in ("", trace_defines):
        if args.authoritative_owner:
            for name in ("MOVEB", "RRTRAP"):
                options = (f"-Mx -t -DI386 -DNoBugMode -DNOHIMEM {define}"
                           " -I. -I..\\EMM -I..\\..\\INC -I..\\..\\DEV\\HIMEM")
                if name == "RRTRAP":
                    options += " -DRRTRAP_LOW_ONLY"
                subprocess.run([str(capture.ROOT / "bin/jwasm-masm"), options,
                                f"{name}.ASM,{name}.OBJ;"], cwd=build, check=True,
                               stdout=subprocess.DEVNULL)
        if args.table_layout:
            for name in ("EMMINIT", "INITTAB", "SHIPHI", "TABDEF"):
                subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                                f"-Mx -t -DI386 -DNoBugMode -DNOHIMEM {define} -I. -I..\\EMM",
                                f"{name}.ASM,{name}.OBJ;"], cwd=build, check=True,
                               stdout=subprocess.DEVNULL)
            subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                            f"-Mx -t -DI386 -DNoBugMode -DNOHIMEM {define} -I..\\MEMM",
                            "EMMSUP.ASM,EMMSUP.OBJ;"], cwd=work / "MEMM/EMM", check=True,
                           stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                        f"-Mx -t -DI386 -DNoBugMode -DNOHIMEM {define} -I. -I..\\EMM",
                        "INIT.ASM,INIT.OBJ;"], cwd=build, check=True,
                       stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/wlink"), "/NOI /PACKDATA:1 @EMM386.LNK"],
                       cwd=build, check=True, stdout=subprocess.DEVNULL)
        if not define and capture.sha256(build / "EMM386.EXE") != original:
            raise RuntimeError("default reconstruction differs from production; rebuild memm first")
    qexit = work / "QEXIT.COM"
    himem = capture.ROOT / "src/DEV/HIMEM/HIMEM.SYS"
    if args.authoritative_owner:
        himem = work / "HIMEM.SYS"
        subprocess.run([str(capture.ROOT / "bin/jwasm-bin"), "-q", "-bin", "-Sa",
                        f"-Fl={work / 'HIMEM.LST'}",
                        *(["-DHIMEM_UMB_LEGACY_BOUND_TEST"] if args.bad_umb_bound else []),
                        *(["-DHIMEM_UMB_HANDOFF_TEST"] if args.umb_handoff else []),
                        *(["-DHIMEM_UMB_RESULTS_TEST"] if args.umb_service_receipts else []),
                        *(["-DHIMEM_COMMON_XMS_TEST"] if args.common_xms_entry else []),
                        *(["-DHIMEM_COMMON_OLD_HANDLE_TEST"] if args.bad_common_frame else []),
                        *(["-DHIMEM_BIND_ALWAYS_DISCOVER_TEST"] if args.bad_common_binding == "rediscover" else []),
                        *(["-DHIMEM_COMMON_LOW_MOVE_TEST"] if args.bad_common_move_low else []),
                        *(["-DHIMEM_UMB_SEQUENCE_WRAP_TEST"] if args.umb_sequence_wrap else []),
                        *(["-DHIMEM_UMB_RESULTS_NO_FREEZE_TEST"] if args.bad_umb_result_freeze else []),
                        *(["-DHIMEM_UMB_DEFER_TEST"] if args.umb_live_import else []),
                        *(["-DHIMEM_UMB_HANDOFF_LOCAL_TEST"] if args.bad_umb_low_owner else []),
                        *(["-DHIMEM_BOOTSTRAP_STAGE_TEST"] if args.stage_bootstrap else []),
                        *(["-DHIMEM_BOOTSTRAP_BAD_LAYOUT"] if args.bad_bootstrap_layout else []),
                        "-DHIMEM_PROTECTED_COPY_TEST", "-DHIMEM_PROTECTED_OWNER_TEST",
                        "-DHIMEM_AUTHORITATIVE_OWNER_TEST", "-DHIMEM_AUTHORITATIVE_POISON_TEST",
                        f"-I{work / 'INC'}", f"-Fo{himem}",
                        str(work / "DEV/HIMEM/HIMEM.ASM")], check=True)
    loader_image = None
    loader_hash = None
    if args.loader:
        loader_image, loader_hash = build_loader(
            work, rejected=args.reject_prepared, bad_version=args.loader_bad_version,
            rebase=args.loader_rebase, bad_rebase=args.loader_bad_rebase,
            stage_bootstrap=args.stage_bootstrap, reclaim_bootstrap=args.reclaim_bootstrap)
    subprocess.run(["nasm", "-f", "bin", str(capture.QEMU_EXIT_SOURCE),
                    "-o", str(qexit)], check=True)
    owner_probe = work / "OWNER.COM"
    capacity_probe = work / "CAPACITY.COM"
    handle_probe = work / "HANDLES.COM"
    if args.handles is not None:
        subprocess.run(["nasm", "-f", "bin", f"-DHANDLES={args.handles}",
                        str(capture.ROOT / "tests/emm_handle_capacity_probe.asm"),
                        "-o", str(handle_probe)], check=True)
    if args.altregs is not None:
        subprocess.run(["nasm", "-f", "bin", f"-DALTREGS={args.altregs}",
                        *(["-DSWITCH_SETS"] if args.switch_altregs else []),
                        str(capture.ROOT / "tests/emm_altreg_capacity_probe.asm"),
                        "-o", str(capacity_probe)], check=True)
    if args.loader:
        mark_delta = 32 if args.loader_rebase and not (args.reclaim_bootstrap or args.loader_bad_rebase) else 0
        umb_defines = []
        if args.umb_coalesce:
            symbols, _ = parse_symbols(work / "HIMEM.LST")
            start, size = symbols["umb_blocks"]
            umb_defines = [f"-DUMB_GUARD_OFFSET={start + size}"]
            if args.common_xms_entry:
                procedures = {}
                for line in (work / "HIMEM.LST").read_text(encoding="latin-1").splitlines():
                    match = PROCEDURE_RE.match(line)
                    if match:
                        procedures[match[1]] = int(match[2], 16)
                umb_defines += ["-DCOMMON_PUBLIC_MOVE",
                                f"-DMOVE_RESOLVER_OFFSET={procedures['resolve_move_address']}"]
                ready = []
                for line in (build / "EMM386.MAP").read_text().splitlines():
                    fields = line.split()
                    if len(fields) == 2 and fields[1] == "XmsBindingReady":
                        ready.append(int(fields[0].rstrip("*+").split(":")[1], 16))
                if len(ready) != 1:
                    raise ValueError("missing/duplicate common binding guard in linked map")
                umb_defines += [f"-DCOMMON_BINDING_OFFSET={symbols['xms_bound_entry'][0]}",
                                f"-DCOMMON_GUARD_OFFSET={ready[0]}",
                                f"-DCOMMON_OWNER_PACKET_OFFSET={symbols['owner_packet'][0]}",
                                f"-DCOMMON_UMB_PACKET_OFFSET={symbols['umb_remote_packet'][0]}",
                                f"-DCOMMON_COPY_PACKET_OFFSET={symbols['protected_copy_packet'][0]}"]
            if args.umb_handoff:
                umb_defines += ["-DUMB_LOW_FALLBACK_TEST" if args.reject_prepared else "-DUMB_HANDOFF_TEST",
                                f"-DUMB_STATE_OFFSET={symbols['umb_remote_state'][0]}"]
                if args.umb_lost_import_reply:
                    umb_defines += ["-DUMB_LOST_IMPORT_REPLY"]
                if args.umb_refused_import:
                    umb_defines += ["-DUMB_REFUSED_IMPORT"]
                if args.umb_live_import:
                    umb_defines += ["-DUMB_LIVE_IMPORT",
                                    f"-DUMB_DEFER_OFFSET={symbols['umb_remote_defer'][0]}"]
                if args.umb_service_receipts:
                    umb_defines += ["-DUMB_SERVICE_RECEIPTS",
                                    f"-DUMB_SEQUENCE_OFFSET={symbols['umb_remote_sequence'][0]}",
                                    f"-DUMB_RECOVERED_OFFSET={symbols['umb_remote_recovered'][0]}",
                                    f"-DUMB_NOT_EXECUTED_OFFSET={symbols['umb_remote_not_executed'][0]}"]
                    if args.umb_service_reply:
                        umb_defines += [{"before": "-DUMB_REPLY_BEFORE", "after": "-DUMB_REPLY_AFTER",
                                         "unknown": "-DUMB_REPLY_UNKNOWN"}[args.umb_service_reply],
                                        f"-DUMB_PACKET_OFFSET={symbols['common_packet' if args.common_xms_entry else 'umb_remote_packet'][0]}",
                                        f"-DUMB_PENDING_BYTES={156 if args.common_xms_entry else 24}"]
        subprocess.run(["nasm", "-f", "bin", f"-DEMM_MARK_DELTA={mark_delta}",
                        *(["-DUMB_OWNER_TEST"] if args.umb_owner else []),
                        *umb_defines, f"-I{capture.ROOT}/",
                        str(capture.ROOT / "tests/emm_provider_owner_probe.asm"),
                        "-o", str(owner_probe)], check=True)
    records = {}
    owner_counts = {}
    post_boot = {}
    for mode in ("ON", "OFF", "AUTO", "RAM"):
        image = work / f"{mode}.img"
        shutil.copyfile(args.image, image)
        if args.authoritative_owner:
            capture.install_file(image, capture.ROOT / "src/DOS/MSDOS.SYS", "MSDOS.SYS")
            capture.install_file(image, capture.ROOT / "src/CMD/COMMAND/COMMAND.COM", "COMMAND.COM")
        if args.handles is not None:
            capture.install_file(image, handle_probe, "HANDLES.COM")
        if args.altregs is not None:
            capture.install_file(image, capacity_probe, "CAPACITY.COM")
        if loader_image:
            capture.install_file(image, loader_image, "IO.SYS")
            capture.install_file(image, owner_probe, "OWNER.COM")
        for source, name in ((build / "EMM386.EXE", "EMM386.EXE"),
                             (himem, "HIMEM.SYS"),
                             (qexit, "QEXIT.COM")):
            capture.install_file(image, source, name)
        config = work / f"{mode}-CONFIG.SYS"
        capacities = "".join(f" {key}={value}" for key, value in
                             (("H", args.handles), ("A", args.altregs)) if value is not None)
        config.write_bytes((f"DEVICE=HIMEM.SYS /TESTMEM:OFF /NUMHANDLES={args.xms_handles}\r\n"
                            f"DEVICE=EMM386.EXE {mode}{capacities}\r\n"
                            f"DOS={'HIGH' if args.dos_high else 'LOW'}\r\n").encode())
        batch = work / "AUTOEXEC.BAT"
        batch.write_bytes(b"@ECHO OFF\r\n" + (b"OWNER.COM\r\n" if args.loader else b"")
                          + (b"EMM386.EXE ON\r\nHANDLES.COM\r\n" if args.handles is not None else b"")
                          + (b"EMM386.EXE ON\r\nCAPACITY.COM\r\n" if args.altregs is not None else b"")
                          + b"QEXIT.COM\r\n")
        capture.install_file(image, config, "CONFIG.SYS")
        capture.install_file(image, batch, "AUTOEXEC.BAT")
        trace = work / f"{mode}.bin"
        with (work / f"{mode}.log").open("wb") as log:
            process = subprocess.run([
                "qemu-system-i386", *capture.hardware_args(), "-display", "none",
                "-monitor", "none", "-serial", "stdio", "-no-reboot", "-boot", "a",
                "-drive", f"if=floppy,format=raw,file={image}",
                "-debugcon", f"file:{trace}", "-global", "isa-debugcon.iobase=0xe9",
                "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                stdout=log, stderr=subprocess.STDOUT, timeout=35)
        if process.returncode != 33:
            raise RuntimeError(f"guest did not finish {mode}: {process.returncode}")
        trace_data = strip_capacity_records(trace.read_bytes(), handles=args.handles,
                                             altregs=args.altregs)
        if args.loader:
            expected = 0 if args.reject_prepared else 1
            if not trace_data.endswith(b"DO" + struct.pack("<H", expected)):
                raise ValueError("unexpected installed EMM device owner count")
            owner_counts[mode] = expected
            trace_data = trace_data[:-4]
            post_boot[mode] = parse_post_boot(trace_data[-10:], expected)
            trace_data = trace_data[:-10]
            if args.common_xms_entry and args.umb_service_reply != "unknown":
                if not trace_data.endswith(b"CF"):
                    raise ValueError("common frame/legacy packet independence probe failed")
                trace_data = trace_data[:-2]
                post_boot[mode]["common_frame"] = dict(legacy_packet_bytes_unused=64)
                post_boot[mode]["common_binding"] = parse_common_binding(trace_data[-8:])
                trace_data = trace_data[:-8]
                if not trace_data.endswith(b"PM"):
                    raise ValueError("common public Move/retired-resolver probe failed")
                trace_data = trace_data[:-2]
                post_boot[mode]["common_public_move"] = dict(low_resolver_unused=True,
                                                           descriptor_validation=True)
            if args.umb_service_receipts:
                post_boot[mode]["umb_service_receipt"] = parse_umb_service_receipt(
                    trace_data[-10:], failure=args.umb_service_reply, common_frame=args.common_xms_entry)
                trace_data = trace_data[:-10]
            if args.umb_live_import:
                post_boot[mode]["live_umb_import"] = parse_live_umb_import(trace_data[-8:], mode=mode)
                trace_data = trace_data[:-8]
            if args.umb_handoff and not args.reject_prepared and args.umb_service_reply != "unknown":
                post_boot[mode]["umb_handoff"] = parse_umb_handoff(trace_data[-8:], mode=mode)
                trace_data = trace_data[:-8]
            if args.umb_owner:
                post_boot[mode]["private_umb_owner"] = parse_private_umb_receipt(trace_data[-8:])
                trace_data = trace_data[:-8]
            if args.umb_coalesce and args.umb_service_reply != "unknown":
                post_boot[mode]["umb_synthetic_registration"] = parse_umb_receipt(
                    trace_data[-3:], mode=mode, rejected=args.reject_prepared)
                trace_data = trace_data[:-3]
        records[mode] = parse_trace(trace_data, split=args.split_prepare,
                                   rejected=args.reject_prepared,
                                   activation_stack=args.activation_stack,
                                   lifecycle=args.lifecycle,
                                   loader=args.loader and not args.loader_bad_version,
                                   rebase=args.loader_rebase, table_layout=args.table_layout,
                                   bootstrap_owner=args.bootstrap_owner,
                                   authoritative_owner=args.authoritative_owner,
                                   rebase_rejected=args.loader_bad_rebase,
                                   reclaim_bootstrap=args.reclaim_bootstrap)
        if args.authoritative_owner:
            live = records[mode][-1]["bootstrap_owner"]["layout"]
            linked = bootstrap_layout(work / "HIMEM.LST", live["handles"])
            if (live["permanent_bytes"] != linked["permanent_bytes"]
                    or live["records_offset"] != linked["permanent_bytes"] + linked["bootstrap_code_data_bytes"]
                    or live["boot_end"] != linked["linked_boot_end"]):
                raise ValueError("runtime bootstrap layout differs from linked owner")
            reclaimed = args.reclaim_bootstrap and not args.reject_prepared
            expected_himem = live["permanent_bytes"] if reclaimed else live["boot_end"]
            if post_boot[mode]["himem_bytes"] != expected_himem:
                raise ValueError("post-boot HIMEM allocation disagrees with lifetime boundary")
        if args.table_layout:
            layout = next(row["tables"] for row in records[mode] if "tables" in row)
            if layout["high"] != int(args.high_tables):
                raise ValueError("table placement fell back from the requested owner")
            layout["resident_bytes"] = (
                layout["end"] - int(records[mode][-1]["int67"].split(":")[0], 16)) * 16
            if args.loader and (not args.loader_rebase or args.reclaim_bootstrap):
                if layout["resident_bytes"] != post_boot[mode]["emm_bytes"]:
                    raise ValueError("table-layout break disagrees with post-boot EMM allocation")
        check_phases(records[mode], mode, split=args.split_prepare,
                     rejected=args.reject_prepared, activation_stack=args.activation_stack,
                     lifecycle=args.lifecycle,
                     loader=args.loader and not args.loader_bad_version,
                     rebase=args.loader_rebase)
        print(mode, json.dumps(records[mode]), flush=True)
    if capture.sha256(args.image) != image_hash:
        raise RuntimeError("input image changed")
    (work / "result.json").write_text(json.dumps(dict(
        input_sha256=image_hash, normal_emm_sha256=original,
        trace_emm_sha256=capture.sha256(build / "EMM386.EXE"),
        split_prepare=args.split_prepare, rejected=args.reject_prepared,
        poison_request=args.poison_request,
        activation_stack=args.activation_stack,
        lifecycle=args.lifecycle,
        loader=args.loader, loader_bad_version=args.loader_bad_version,
        loader_rebase=args.loader_rebase,
        loader_move_rejected=args.loader_bad_rebase,
        bootstrap_owner=args.bootstrap_owner,
        authoritative_owner=args.authoritative_owner, himem_sha256=capture.sha256(himem),
        bad_owner_receipt=args.bad_owner_receipt,
        bad_bootstrap_layout=args.bad_bootstrap_layout,
        stage_bootstrap=args.stage_bootstrap,
        reclaim_bootstrap=args.reclaim_bootstrap,
        umb_coalesce=args.umb_coalesce,
        umb_owner=args.umb_owner,
        umb_handoff=args.umb_handoff,
        umb_service_receipts=args.umb_service_receipts,
        common_xms_entry=args.common_xms_entry,
        bad_common_xms_entry=args.bad_common_xms_entry,
        bad_common_move_low=args.bad_common_move_low,
        bad_common_binding=args.bad_common_binding,
        bad_common_frame=args.bad_common_frame,
        umb_sequence_wrap=args.umb_sequence_wrap,
        umb_service_reply=args.umb_service_reply,
        bad_umb_result_freeze=args.bad_umb_result_freeze,
        umb_live_import=args.umb_live_import,
        bad_umb_import_bits=args.bad_umb_import_bits,
        umb_lost_import_reply=args.umb_lost_import_reply,
        umb_refused_import=args.umb_refused_import,
        bad_umb_low_owner=args.bad_umb_low_owner,
        bad_umb_route=args.bad_umb_route,
        bad_umb_bound=args.bad_umb_bound,
        skip_stage_retarget=args.skip_stage_retarget,
        xms_handles=args.xms_handles,
        dos_high=args.dos_high,
        dos_sha256=capture.sha256(capture.ROOT / "src/DOS/MSDOS.SYS")
            if args.authoritative_owner else None,
        command_sha256=capture.sha256(capture.ROOT / "src/CMD/COMMAND/COMMAND.COM")
            if args.authoritative_owner else None,
        high_tables=args.high_tables, table_layout=args.table_layout,
        handles=args.handles, altregs=args.altregs,
        switch_altregs=args.switch_altregs,
        installed_owner_counts=owner_counts,
        post_boot=post_boot,
        owner_probe_sha256=capture.sha256(owner_probe) if args.loader else None,
        loader_dynamic_staging=bool(loader_image),
        rebase_manifest=rebase_manifest((build / "EMM386.EXE").read_bytes())
            if args.loader_rebase else None,
        normal_bios_sha256=loader_hash,
        loader_bios_sha256=capture.sha256(loader_image) if loader_image else None,
        emulator=capture.qemu_identity(), records=records), indent=2) + "\n")


if __name__ == "__main__":
    main()
