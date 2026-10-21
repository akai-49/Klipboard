#!/usr/bin/env python3
"""
Builds a compressed macOS drag-and-drop installer DMG (UDZO / HFS+) containing:
  - Klipboard.app (left icon)
  - Applications -> /Applications symlink (right icon)
  - .DS_Store configured for Finder Icon View (drag-to-Applications layout)
"""

import os
import plistlib
import stat
import struct
import sys
import time
import zlib
from pathlib import Path

BLOCK_SIZE = 4096
SECTOR_SIZE = 512
HFS_EPOCH_OFFSET = 2082844800

K_HFS_ROOT_PARENT_ID = 1
K_HFS_ROOT_FOLDER_ID = 2
K_HFS_EXTENTS_FILE_ID = 3
K_HFS_CATALOG_FILE_ID = 4
K_HFS_BAD_BLOCKS_FILE_ID = 5
K_HFS_ALLOCATION_FILE_ID = 6
K_HFS_STARTUP_FILE_ID = 7
K_HFS_ATTRIBUTES_FILE_ID = 8
K_HFS_FIRST_USER_CNID = 16

K_HFS_PLUS_FOLDER_RECORD = 0x0001
K_HFS_PLUS_FILE_RECORD = 0x0002
K_HFS_PLUS_FOLDER_THREAD_RECORD = 0x0003
K_HFS_PLUS_FILE_THREAD_RECORD = 0x0004


def make_ds_store(entries_coords):
    """Creates a Finder .DS_Store B-tree setting icnv view and Iloc icon positions."""
    records = []

    def ustr(s):
        b = s.encode("utf-16be")
        return struct.pack(">I", len(s)) + b

    def rec(filename, code, dtype, payload):
        return ustr(filename) + code.encode("ascii") + dtype.encode("ascii") + payload

    bwsp_plist = plistlib.dumps(
        {
            "ContainerShowSidebar": False,
            "ShowPathbar": False,
            "ShowSidebar": False,
            "ShowStatusBar": False,
            "ShowTabView": False,
            "ShowToolbar": False,
            "WindowBounds": "{{220, 180}, {560, 340}}",
        },
        fmt=plistlib.FMT_BINARY,
    )
    icvp_plist = plistlib.dumps(
        {
            "arrangeBy": "none",
            "backgroundColorBlue": 0.96,
            "backgroundColorGreen": 0.96,
            "backgroundColorRed": 0.96,
            "backgroundType": 1,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "iconSize": 104.0,
            "labelOnBottom": True,
            "showIconPreview": True,
            "showItemInfo": False,
            "textSize": 13.0,
            "viewOptionsVersion": 1,
        },
        fmt=plistlib.FMT_BINARY,
    )
    records.append((".", "bwsp", rec(".", "bwsp", "blob", struct.pack(">I", len(bwsp_plist)) + bwsp_plist)))
    records.append((".", "icvp", rec(".", "icvp", "blob", struct.pack(">I", len(icvp_plist)) + icvp_plist)))
    records.append((".", "vSrn", rec(".", "vSrn", "long", struct.pack(">I", 1))))

    for name, (x, y) in entries_coords.items():
        iloc = struct.pack(">IIII", x, y, 0xFFFFFFFF, 0)
        records.append((name, "Iloc", rec(name, "Iloc", "blob", struct.pack(">I", len(iloc)) + iloc)))

    records.sort(key=lambda r: (r[0].lower(), r[1]))
    node_body = b"".join(r[2] for r in records)
    node_header = struct.pack(">II", 0, len(records))
    node_data = (node_header + node_body).ljust(4096, b"\x00")

    dsdb = struct.pack(">IIIII", 1, 0, 1, 1, 4096)

    addr_dsdb = 0x0040 | 5
    addr_root = 0x1000 | 12
    addr_toc = 0x0080 | 11

    toc = bytearray()
    toc += struct.pack(">II", 3, 0)
    toc += struct.pack(">III", addr_dsdb, addr_root, addr_toc)
    toc += struct.pack(">I", 1)
    toc += struct.pack(">B", 4) + b"DSDB" + struct.pack(">I", 0)
    for _ in range(32):
        toc += struct.pack(">I", 0)

    toc_padded = bytes(toc).ljust(2048, b"\x00")
    bud1 = struct.pack(">4sIII", b"Bud1", 0x0080, 2048, 0x0080) + b"\x00" * 16

    buf = bytearray(0x2000)
    buf[0:4] = struct.pack(">I", 1)
    buf[4:36] = bud1
    buf[0x40 : 0x40 + len(dsdb)] = dsdb
    buf[0x80 : 0x80 + 2048] = toc_padded
    buf[0x1000 : 0x1000 + 4096] = node_data
    return bytes(buf)


def hfs_str_key(s: str) -> bytes:
    u16 = s.encode("utf-16be")
    return struct.pack(">H", len(u16) // 2) + u16


def pack_fork_data(logical_size: int, start_block: int, block_count: int) -> bytes:
    extents = bytearray(64)
    if block_count > 0:
        struct.pack_into(">II", extents, 0, start_block, block_count)
    res = struct.pack(">QII", logical_size, block_count * BLOCK_SIZE, block_count) + bytes(extents)
    assert len(res) == 80
    return res


def build_hfs_plus_image(vol_name: str, app_path: Path) -> bytes:
    now_hfs = int(time.time()) + HFS_EPOCH_OFFSET

    nodes = []
    next_cnid = K_HFS_FIRST_USER_CNID

    root_node = {
        "cnid": K_HFS_ROOT_FOLDER_ID,
        "parent_cnid": K_HFS_ROOT_PARENT_ID,
        "name": vol_name,
        "kind": "dir",
        "mode": stat.S_IFDIR | 0o755,
        "data": b"",
        "children": [],
        "finder_flags": 0,
    }
    nodes.append(root_node)

    # 1. .DS_Store in root for drag-to-Applications icon positions
    ds_store_bytes = make_ds_store({"Klipboard.app": (155, 165), "Applications": (405, 165)})
    ds_node = {
        "cnid": next_cnid,
        "parent_cnid": K_HFS_ROOT_FOLDER_ID,
        "name": ".DS_Store",
        "kind": "file",
        "mode": stat.S_IFREG | 0o644,
        "data": ds_store_bytes,
        "creator": b"\x00\x00\x00\x00",
        "ftype": b"\x00\x00\x00\x00",
        "finder_flags": 0x4000,
    }
    next_cnid += 1
    root_node["children"].append(ds_node)
    nodes.append(ds_node)

    # 2. Applications symlink -> /Applications
    sym_node = {
        "cnid": next_cnid,
        "parent_cnid": K_HFS_ROOT_FOLDER_ID,
        "name": "Applications",
        "kind": "symlink",
        "mode": stat.S_IFLNK | 0o755,
        "data": b"/Applications",
        "creator": b"rhap",
        "ftype": b"slnk",
        "finder_flags": 0,
    }
    next_cnid += 1
    root_node["children"].append(sym_node)
    nodes.append(sym_node)

    # 3. Recursively add Klipboard.app
    def add_tree(fs_path: Path, parent_dir_node: dict):
        nonlocal next_cnid
        st = fs_path.lstat()
        cnid = next_cnid
        next_cnid += 1
        if stat.S_ISLNK(st.st_mode):
            target = os.readlink(fs_path).encode("utf-8")
            n = {
                "cnid": cnid,
                "parent_cnid": parent_dir_node["cnid"],
                "name": fs_path.name,
                "kind": "symlink",
                "mode": stat.S_IFLNK | 0o755,
                "data": target,
                "creator": b"rhap",
                "ftype": b"slnk",
                "finder_flags": 0,
            }
            parent_dir_node["children"].append(n)
            nodes.append(n)
        elif stat.S_ISDIR(st.st_mode):
            is_bundle = fs_path.name.endswith(".app")
            n = {
                "cnid": cnid,
                "parent_cnid": parent_dir_node["cnid"],
                "name": fs_path.name,
                "kind": "dir",
                "mode": stat.S_IFDIR | (st.st_mode & 0o777),
                "data": b"",
                "children": [],
                "finder_flags": 0x2000 if is_bundle else 0,
            }
            parent_dir_node["children"].append(n)
            nodes.append(n)
            for child in sorted(fs_path.iterdir(), key=lambda p: p.name.lower()):
                if child.name == ".DS_Store":
                    continue
                add_tree(child, n)
        elif stat.S_ISREG(st.st_mode):
            raw = fs_path.read_bytes()
            n = {
                "cnid": cnid,
                "parent_cnid": parent_dir_node["cnid"],
                "name": fs_path.name,
                "kind": "file",
                "mode": stat.S_IFREG | (st.st_mode & 0o777),
                "data": raw,
                "creator": b"\x00\x00\x00\x00",
                "ftype": b"\x00\x00\x00\x00",
                "finder_flags": 0,
            }
            parent_dir_node["children"].append(n)
            nodes.append(n)

    add_tree(app_path, root_node)

    CAT_NODE_SIZE = 8192
    CAT_BLOCKS = 8
    cur_block = 1 + 1 + 1 + CAT_BLOCKS  # starts at block 11

    file_count = 0
    folder_count = 0

    for n in nodes:
        if n["kind"] == "dir":
            if n["cnid"] != K_HFS_ROOT_FOLDER_ID:
                folder_count += 1
            n["start_block"] = 0
            n["block_count"] = 0
        else:
            file_count += 1
            size = len(n["data"])
            if size == 0:
                n["start_block"] = 0
                n["block_count"] = 0
            else:
                bcount = (size + BLOCK_SIZE - 1) // BLOCK_SIZE
                n["start_block"] = cur_block
                n["block_count"] = bcount
                cur_block += bcount

    total_blocks = max(cur_block + 64, 1024)
    used_blocks_end = cur_block

    cat_records = []

    for n in nodes:
        key_body = struct.pack(">I", n["parent_cnid"]) + hfs_str_key(n["name"])
        key = struct.pack(">H", len(key_body)) + key_body

        # HFSPlusBSDInfo (16 bytes): ownerID=99 (unknown), groupID=99 (unknown), adminFlags=0, ownerFlags=0, fileMode, special=0
        bsd_info = struct.pack(">IIBBHI", 99, 99, 0, 0, n["mode"], 0)

        if n["kind"] == "dir":
            valence = len(n["children"])
            f_info = struct.pack(">hhhhHhhh", 0, 0, 0, 0, n.get("finder_flags", 0), 0, 0, 0)
            fx_info = b"\x00" * 16
            rec_data = (
                struct.pack(
                    ">HHIIIIIII",
                    K_HFS_PLUS_FOLDER_RECORD,
                    0,
                    valence,
                    n["cnid"],
                    now_hfs,
                    now_hfs,
                    now_hfs,
                    now_hfs,
                    0,
                )
                + bsd_info
                + f_info
                + fx_info
                + struct.pack(">II", 0, 0)
            )
            assert len(rec_data) == 88
        else:
            f_info = struct.pack(
                ">4s4sHhhh",
                n.get("ftype", b"\x00\x00\x00\x00"),
                n.get("creator", b"\x00\x00\x00\x00"),
                n.get("finder_flags", 0),
                0,
                0,
                0,
            )
            fx_info = b"\x00" * 16
            data_fork = pack_fork_data(len(n["data"]), n["start_block"], n["block_count"])
            rsrc_fork = pack_fork_data(0, 0, 0)
            rec_data = (
                struct.pack(
                    ">HHIIIIIII",
                    K_HFS_PLUS_FILE_RECORD,
                    0x0002,
                    0,
                    n["cnid"],
                    now_hfs,
                    now_hfs,
                    now_hfs,
                    now_hfs,
                    0,
                )
                + bsd_info
                + f_info
                + fx_info
                + struct.pack(">II", 0, 0)
                + data_fork
                + rsrc_fork
            )
            assert len(rec_data) == 248

        cat_records.append((n["parent_cnid"], n["name"].lower(), key + rec_data))

        t_key_body = struct.pack(">IH", n["cnid"], 0)
        t_key = struct.pack(">H", len(t_key_body)) + t_key_body
        t_type = K_HFS_PLUS_FOLDER_THREAD_RECORD if n["kind"] == "dir" else K_HFS_PLUS_FILE_THREAD_RECORD
        t_data = struct.pack(">HHI", t_type, 0, n["parent_cnid"]) + hfs_str_key(n["name"])
        cat_records.append((n["cnid"], "", t_key + t_data))

    cat_records.sort(key=lambda item: (item[0], item[1]))

    cat_total_nodes = (CAT_BLOCKS * BLOCK_SIZE) // CAT_NODE_SIZE
    leaf_records_bytes = [r[2] for r in cat_records]

    leaf_node = bytearray(CAT_NODE_SIZE)
    struct.pack_into(">IIbBHH", leaf_node, 0, 0, 0, -1, 1, len(leaf_records_bytes), 0)
    pos = 14
    offsets = [pos]
    for rb in leaf_records_bytes:
        leaf_node[pos : pos + len(rb)] = rb
        pos += len(rb)
        offsets.append(pos)
    for idx, off in enumerate(offsets):
        struct.pack_into(">H", leaf_node, CAT_NODE_SIZE - 2 * (idx + 1), off)

    cat_header_node = bytearray(CAT_NODE_SIZE)
    struct.pack_into(">IIbBHH", cat_header_node, 0, 0, 0, 1, 0, 3, 0)
    bt_header_rec = struct.pack(
        ">HIIIIHHIIHIBBI",
        1,
        1,
        len(leaf_records_bytes),
        1,
        1,
        CAT_NODE_SIZE,
        516,
        cat_total_nodes,
        cat_total_nodes - 2,
        0,
        CAT_BLOCKS * BLOCK_SIZE,
        0,
        0xCF,
        0x00000006,
    ) + (b"\x00" * 64)
    assert len(bt_header_rec) == 106

    bt_user_rec = b"\x00" * 128
    bt_map_rec = bytearray(CAT_NODE_SIZE - 256)
    bt_map_rec[0] = 0xC0

    h_pos = 14
    h_offsets = [h_pos]
    for r in (bt_header_rec, bt_user_rec, bytes(bt_map_rec)):
        cat_header_node[h_pos : h_pos + len(r)] = r
        h_pos += len(r)
        h_offsets.append(h_pos)
    for idx, off in enumerate(h_offsets):
        struct.pack_into(">H", cat_header_node, CAT_NODE_SIZE - 2 * (idx + 1), off)

    ext_node = bytearray(BLOCK_SIZE)
    struct.pack_into(">IIbBHH", ext_node, 0, 0, 0, 1, 0, 3, 0)
    ext_header_rec = struct.pack(
        ">HIIIIHHIIHIBBI",
        0, 0, 0, 0, 0,
        BLOCK_SIZE, 10, 1, 0, 0,
        BLOCK_SIZE, 0, 0, 0x00000002,
    ) + (b"\x00" * 64)
    assert len(ext_header_rec) == 106
    ext_map_rec = bytearray(BLOCK_SIZE - 256)
    ext_map_rec[0] = 0x80
    e_pos = 14
    e_offsets = [e_pos]
    for r in (ext_header_rec, bt_user_rec, bytes(ext_map_rec)):
        ext_node[e_pos : e_pos + len(r)] = r
        e_pos += len(r)
        e_offsets.append(e_pos)
    for idx, off in enumerate(e_offsets):
        struct.pack_into(">H", ext_node, BLOCK_SIZE - 2 * (idx + 1), off)

    alloc_bitmap = bytearray(BLOCK_SIZE)
    for b in range(used_blocks_end):
        alloc_bitmap[b // 8] |= 1 << (7 - (b % 8))
    last_b = total_blocks - 1
    alloc_bitmap[last_b // 8] |= 1 << (7 - (last_b % 8))

    free_blocks = total_blocks - used_blocks_end - 1

    alloc_fork = pack_fork_data(BLOCK_SIZE, 1, 1)
    ext_fork = pack_fork_data(BLOCK_SIZE, 2, 1)
    cat_fork = pack_fork_data(CAT_BLOCKS * BLOCK_SIZE, 3, CAT_BLOCKS)
    empty_fork = pack_fork_data(0, 0, 0)

    finder_info = bytearray(32)
    vol_header = (
        struct.pack(
            ">2sHIIIIIIIIIIIIIIIIIQ",
            b"H+",
            4,
            0x00000100,
            0x31302E30,
            0,
            now_hfs,
            now_hfs,
            0,
            now_hfs,
            file_count,
            folder_count,
            BLOCK_SIZE,
            total_blocks,
            free_blocks,
            used_blocks_end,
            65536,
            65536,
            next_cnid,
            1,
            1,
        )
        + bytes(finder_info)
        + alloc_fork
        + ext_fork
        + cat_fork
        + empty_fork
        + empty_fork
    )
    assert len(vol_header) == 512

    img = bytearray(total_blocks * BLOCK_SIZE)
    img[1024 : 1024 + 512] = vol_header
    img[1 * BLOCK_SIZE : 2 * BLOCK_SIZE] = alloc_bitmap
    img[2 * BLOCK_SIZE : 3 * BLOCK_SIZE] = ext_node
    img[3 * BLOCK_SIZE : 3 * BLOCK_SIZE + CAT_NODE_SIZE] = cat_header_node
    img[3 * BLOCK_SIZE + CAT_NODE_SIZE : 3 * BLOCK_SIZE + 2 * CAT_NODE_SIZE] = leaf_node
    for n in nodes:
        if n["kind"] != "dir" and n["block_count"] > 0:
            off = n["start_block"] * BLOCK_SIZE
            img[off : off + len(n["data"])] = n["data"]

    img[len(img) - 1024 : len(img) - 512] = vol_header
    return bytes(img)


def wrap_udzo_dmg(hfs_image: bytes, out_dmg: Path):
    """Wraps a raw HFS+ volume image into a standard compressed Apple UDZO (.dmg) with a koly trailer."""
    total_sectors = len(hfs_image) // SECTOR_SIZE
    chunk_sectors = 2048

    data_fork = bytearray()
    runs = []

    sector = 0
    while sector < total_sectors:
        count = min(chunk_sectors, total_sectors - sector)
        chunk = hfs_image[sector * SECTOR_SIZE : (sector + count) * SECTOR_SIZE]
        if any(chunk):
            comp = zlib.compress(chunk, 9)
            offset = len(data_fork)
            data_fork += comp
            runs.append((0x80000005, sector, count, offset, len(comp)))
        else:
            runs.append((0x00000000, sector, count, 0, 0))
        sector += count

    runs.append((0xFFFFFFFF, total_sectors, 0, len(data_fork), 0))

    mish_header = bytearray(204)
    struct.pack_into(
        ">4sIQQQQIIIIII",
        mish_header,
        0,
        b"mish",
        1,
        0,
        total_sectors,
        0,
        chunk_sectors,
        0,
        0, 0, 0, 0, 0,
    )
    data_crc = zlib.crc32(hfs_image) & 0xFFFFFFFF
    struct.pack_into(">III", mish_header, 72, 2, 32, data_crc)
    struct.pack_into(">I", mish_header, 200, len(runs))

    mish_runs = bytearray()
    for rtype, s_start, s_count, c_off, c_len in runs:
        mish_runs += struct.pack(">I", rtype) + b"\x00\x00\x00\x00" + struct.pack(">QQQQ", s_start, s_count, c_off, c_len)

    mish_blob = bytes(mish_header + mish_runs)

    plist_dict = {
        "resource-fork": {
            "blkx": [
                {
                    "Attributes": "0x0050",
                    "CFName": "Klipboard (Apple_HFS : 0)",
                    "Data": mish_blob,
                    "ID": "-1",
                    "Name": "Klipboard (Apple_HFS : 0)",
                }
            ]
        }
    }
    xml_bytes = plistlib.dumps(plist_dict, fmt=plistlib.FMT_XML)

    xml_offset = len(data_fork)
    xml_length = len(xml_bytes)

    koly = bytearray(512)
    struct.pack_into(">4sIII", koly, 0, b"koly", 4, 512, 1)
    struct.pack_into(">QQQ", koly, 16, 0, 0, len(data_fork))
    struct.pack_into(">QQII", koly, 40, 0, 0, 1, 1)
    struct.pack_into(">QQ", koly, 216, xml_offset, xml_length)
    mish_crc = zlib.crc32(struct.pack(">I", data_crc)) & 0xFFFFFFFF
    struct.pack_into(">III", koly, 360, 2, 32, mish_crc)
    struct.pack_into(">IQ", koly, 488, 1, total_sectors)

    out_dmg.write_bytes(bytes(data_fork) + xml_bytes + bytes(koly))


def main():
    if len(sys.argv) < 3:
        print("Usage: build_dmg.py <path-to-Klipboard.app> <output.dmg>", file=sys.stderr)
        sys.exit(1)

    app_path = Path(sys.argv[1]).resolve()
    out_dmg = Path(sys.argv[2]).resolve()
    hfs_bytes = build_hfs_plus_image("Klipboard", app_path)
    wrap_udzo_dmg(hfs_bytes, out_dmg)
    print(f"Created drag-and-drop DMG: {out_dmg} ({out_dmg.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
