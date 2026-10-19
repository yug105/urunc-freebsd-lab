#!/usr/bin/env python3
"""Print the superblock magic numbers of a block image.

Offsets:
  UFS2: superblock at 65536 (SBLOCK_UFS2), fs_magic at +1372 -> 66908
  UFS1: superblock at 8192 (SBLOCK_UFS1), fs_magic at +1372 -> 9564
  ext2/3/4: superblock at 1024, s_magic at +56 -> 1080
Sources: FreeBSD sys/ufs/ffs/fs.h, file(1) magic/Magdir/filesystems,
util-linux libblkid/src/superblocks/{ufs,ext}.c
"""
import struct
import sys

CHECKS = [
    ("ufs2", 66908, "<I", 0x19540119),
    ("ufs1", 9564, "<I", 0x00011954),
    ("ext2", 1080, "<H", 0xEF53),
]


def main(path):
    found = "unknown"
    with open(path, "rb") as f:
        for name, off, fmt, want in CHECKS:
            f.seek(off)
            raw = f.read(struct.calcsize(fmt))
            got = struct.unpack(fmt, raw)[0] if len(raw) == struct.calcsize(fmt) else None
            ok = got == want
            print(f"{name:5} @{off:<6} got={hex(got) if got is not None else 'short'} want={hex(want)} {'MATCH' if ok else ''}")
            if ok and found == "unknown":
                found = name
    print(f"detected: {found}")


if __name__ == "__main__":
    main(sys.argv[1])
