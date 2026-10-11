#!/usr/bin/env python3
"""Rebrand the two fixed title strings in the verified stable No2Theft preferences binary.

No code or function hooks change. Updates only two CFString pointers/lengths
per architecture, storing the new strings in existing mapped data padding.
Re-sign the Mach-O using ldid after applying this patch.
"""
import struct
import sys
from pathlib import Path

NEW = [
    (0x8268, 0x71F0, b"No2Theft iOS 16", 0x8600, b"No2Theft Enhanced iOS16"),
    (0x8288, 0x7200, b"by Elias Sfeir", 0x8620, b"By 551UK"),
]

def patch(path):
    p = Path(path)
    data = bytearray(p.read_bytes())
    magic, count = struct.unpack_from(">II", data, 0)
    assert magic == 0xCAFEBABE and count == 2, "Unknown Mach-O architecture"
    seen = set()
    for i in range(count):
        cpu, subtype, offset, size, align = struct.unpack_from(">IIIII", data, 8 + 20 * i)
        assert cpu == 0x0100000C and subtype in (0, 0x80000002)
        assert subtype not in seen and offset + size <= len(data)
        seen.add(subtype)
        assert data[offset + 0x8580:offset + 0x8660] == b"\0" * 0xE0, "Unexpected padding bytes"
        target_mask = (1 << (43 if subtype == 0x80000002 else 36)) - 1
        for cf_off, old_addr, old_string, new_addr, new_string in NEW:
            assert data[offset + old_addr:offset + old_addr + len(old_string) + 1] == old_string + b"\0"
            ptr_at = offset + cf_off + 16
            current, = struct.unpack_from("<Q", data, ptr_at)
            length, = struct.unpack_from("<Q", data, ptr_at + 8)
            assert current & target_mask == old_addr and length == len(old_string)
            assert new_addr + len(new_string) + 1 < 0x8700
            data[offset + new_addr:offset + new_addr + len(new_string) + 1] = new_string + b"\0"
            struct.pack_into("<Q", data, ptr_at, (current & ~target_mask) | new_addr)
            struct.pack_into("<Q", data, ptr_at + 8, len(new_string))
    assert seen == {0, 0x80000002}
    p.write_bytes(data)
    for i in range(count):
        _, subtype, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + 20 * i)
        for cf_off, old_addr, old_string, new_addr, new_string in NEW:
            assert data[offset + new_addr:offset + new_addr + len(new_string) + 1] == new_string + b"\0"
    print("PASS: title strings adjusted in arm64 and arm64e CFStrings")

if __name__ == "__main__":
    assert len(sys.argv) == 2
    patch(sys.argv[1])
