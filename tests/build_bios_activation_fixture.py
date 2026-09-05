"""Generate private live-activation probe operands from a matched low/high pair."""
import re
from build_bios_low_image import ROOT


def write_fixture(output, low, high):
    symbols, exports = low["symbols"], high["exports"]
    entries = re.findall(r"^BIOS_DEVICE_ENTRY (\d+),([^,]+),([^,]+),([^\s]+)$",
                         (ROOT / "src/BIOS/HIGHDEV.INC").read_text(), re.M)
    size = symbols["BIOS_SERVICE_END"] - symbols["BIOS_SERVICE_START"]
    if size % 2 or high["low_image_sha256"] != low["sha256"]:
        raise ValueError("invalid service range or mismatched low/high images")
    definitions = {"ORIGINAL_BLOCK13": symbols["BLOCK13"],
                   "NEW_BLOCK13": symbols["BIOS_LOW_BLOCK13"],
                   "OLD_SERVICE_START": symbols["BIOS_SERVICE_START"],
                   "OLD_SERVICE_SIZE": size,
                   "ACTIVATION_FIXUP_COUNT": len(high["offset_fixups"])}
    preflight, bind_high, bind_low = [], [], []
    data = ["activation_fixups:", "dw " + ",".join(map(str, high["offset_fixups"]))]
    for command, stub, slot, target in entries:
        table = symbols["DSKTBL"] + 1 + 2 * int(command)
        preflight += [f"cmp word [es:{table}],{symbols[target]}", "jne fail"]
        bind_low += [f"mov word [es:{table}],{symbols[stub]}"]
    policies = {}
    for index, patch in enumerate(high["boot_patches"].values()):
        original = bytes.fromhex(patch["low_original"])
        flag = f"activation_purged_{index}"
        data += [f"{flag} db 0", f"activation_original_{index}:",
                 "db " + ",".join(map(str, original))]
        preflight += [f"mov si,activation_original_{index}", f"mov di,{patch['low_offset']}",
                      f"mov cx,{len(original)}", "repe cmpsb", f"je activation_checked_{index}",
                      f"mov di,{patch['low_offset']}", f"mov cx,{len(original)}", "mov al,90h",
                      "repe scasb", "jne fail", f"mov byte [{flag}],1", f"activation_checked_{index}:"]
        if patch["policy"] in policies:
            preflight += [f"mov al,[{flag}]", f"cmp al,[{policies[patch['policy']]}]", "jne fail"]
        policies[patch["policy"]] = flag
        bind_high += [f"cmp byte [{flag}],0", f"je activation_keep_{index}", "mov di,bx",
                      f"add di,{patch['offset']}", f"mov cx,{patch['size']}", "mov al,90h",
                      "rep stosb", f"activation_keep_{index}:"]
    for slot in high["runtime_slots"].values():
        value = 0x70 if slot["target"] == "resident low BIOS segment" else symbols[slot["target"].upper()]
        bind_high += [f"mov word [es:bx+{slot['offset']}],{value}"]
        if slot["size"] == 4:
            bind_high += [f"mov word [es:bx+{slot['offset'] + 2}],70h"]
    low_targets = {"BIOS_HIGH_NEAR_ENTRY": ("BIOS_HMA_ENTER_NEAR", 4),
                   "BIOS_HIGH_HARDERR_ENTRY": ("HARDERR", 4),
                   "BIOS_HIGH_HARDERR2_ENTRY": ("HARDERR2", 4),
                   "BIOS_HIGH_BLOCK13_ENTRY": ("BLOCK13", 4)}
    low_targets.update({"BIOS_HIGH_" + name: (name, 2)
                        for name in ("SETDRIVE", "MAPERROR", "READ_SECTOR", "CHECKSINGLE")})
    low_targets.update({slot: (target, 4) for _, _, slot, target in entries})
    for slot, (target, width) in low_targets.items():
        bind_low += ["mov ax,bx", f"add ax,{exports[target]}", f"mov [es:{symbols[slot]}],ax"]
        if width == 4:
            bind_low += [f"mov word [es:{symbols[slot] + 2}],0ffffh"]
    for name, lines in (("defs", [f"{key} equ {value}" for key, value in definitions.items()]),
                        ("preflight", preflight), ("bind-high", bind_high),
                        ("bind-low", bind_low), ("data", data)):
        (output / f"activation-{name}.inc").write_text("\n".join(lines) + "\n")
