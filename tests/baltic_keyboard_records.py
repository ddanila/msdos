"""Independent bounds and command/table checks for the supplemental library."""
import struct


def validate(data):
    def take(offset, size):
        if offset < 0 or size < 0 or offset + size > len(data):
            raise ValueError('record outside library')
        return data[offset:offset+size]
    def word(offset):
        return struct.unpack('<H', take(offset, 2))[0]
    def pointer(offset):
        return struct.unpack('<I', take(offset, 4))[0]
    def require(condition, message):
        if not condition:
            raise ValueError(message)
    require(take(0, 16) == b'\xffKEYB   ' + bytes(8), 'signature')
    require(take(22, 6) == struct.pack('<HHH', 0, 5, 5), 'directory counts')
    expected = [('RU',441,866), ('ET',454,775), ('EE',454,775), ('LV',0,775), ('LT',221,775)]
    sections = {}
    cursor = 28 + 12 * len(expected) + 16 * len(expected)
    for index, (code, identifier, page_id) in enumerate(expected):
        directory = 28 + index * 6
        entry = pointer(directory + 2)
        require(take(directory, 2) == code.encode(), 'language directory')
        require(entry == 88 + 16 * index, 'entry boundary')
        require(word(directory+30) == identifier and pointer(directory+32) == entry, 'identifier directory')
        require(take(entry, 4) == code.encode() + struct.pack('<H', identifier), 'entry identity')
        require(take(entry+8, 2) == b'\x01\x01' and word(entry+10) == page_id, 'page directory')
        logic, page = pointer(entry+4), pointer(entry+12)
        common = logic + word(logic)
        end = page + word(page)
        take(logic, end-logic)
        require(word(common+2) == 65535 and word(common) <= word(16), 'common section')
        require(page == common + word(common) and word(page+2) == page_id, 'page boundary')
        require(word(logic) <= word(20) and word(page) <= word(18), 'allocation bounds')
        if code == 'EE':
            require((logic, page, end) == sections['ET'], 'alias sections')
            continue
        require(logic == cursor, 'section boundary')
        cursor = end
        sections[code] = (logic, page, end)
        if code == 'RU':
            continue  # Its translation tables have a separate retail oracle.
        require(word(logic+2) == 0, 'Baltic features')
        commands, kinds, nesting = logic+4, {}, []
        while commands < common:
            opcode = take(commands, 1)[0]
            high = opcode & 0xf0
            size = {0:2, 0x20:1, 0x30:1, 0x40:2, 0x50:2,
                    0x60:2, 0x70:2, 0x90:3, 0xb0:1}.get(high)
            require(size is not None and commands+size <= common, 'logic opcode')
            if high == 0:
                require(opcode & 7 in (0,3,4,5), 'condition flag')
                nesting.append(False)
            elif high == 0x20:
                require(nesting and not nesting[-1], 'duplicate/unmatched else')
                nesting[-1] = True
            elif high == 0x30:
                require(bool(nesting), 'unmatched endif')
                nesting.pop()
            elif high in (0x40,0x60,0x70):
                state = take(commands+1,1)[0]
                kind = 'flag' if high == 0x60 else 'character'
                require(state not in kinds or kinds[state] == kind, 'state command type')
                kinds[state] = kind
            elif high == 0x90:
                require(opcode == 0x92 and word(commands+1) == 0 and commands+3 == common, 'logic exit')
            commands += size
        require(not nesting, 'unclosed condition')
        states = set()
        for section_start, section_end, common_flags in ((common, page, True), (page, end, False)):
            pos = section_start+4
            while word(pos):
                size, state = word(pos), take(pos+2,1)[0]
                require(size >= 8 and pos+size <= section_end-2, 'state boundary')
                require(state in kinds and state not in states, 'state identity')
                require(word(pos+3) == 65535, 'keyboard mask')
                states.add(state)
                table = pos+7
                scans = []
                require((kinds[state] == 'flag') == common_flags, 'state section')
                if kinds[state] == 'flag':
                    count = word(table)
                    require(size == 9+3*count, 'flag table length')
                    for offset in range(table+2, pos+size, 3):
                        scan, flag, mask = take(offset,3)
                        require(flag == 5 and mask in (128,64,32,16,8), 'dead flag')
                        scans.append(scan)
                else:
                    length = word(table)
                    if length:
                        options, count = take(table+2,2)
                        require(options in (64,80) and length == 4+3*count and size == 9+length, 'character table length')
                        scans = [take(table+4+3*i,1)[0] for i in range(count)]
                        table += length
                    require(word(table) == 0 and table+2 == pos+size, 'table terminator')
                require(len(scans) == len(set(scans)), 'duplicate scan')
                pos += size
            require(pos == section_end-2, 'section terminator')
        require(states == set(kinds), 'missing states')
    require(cursor == len(data), 'library end')
    require(word(16) == max(1120, *(word(logic+word(logic)) for logic,_,_ in sections.values())) and word(18) == max(496, *(end-page for _,page,end in sections.values()))
            and word(20) == max(640, *(word(logic) for logic,_,_ in sections.values())), 'allocation maxima')
    return sections
