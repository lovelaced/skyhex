"""Minimal read-only reader for the local WoW install's CASC storage.

Maps a fileDataID to its bytes for one product build (default: wowf, WoW: Forever), so
dev tools can check that an icon ships with the client and render the real art. Reads
the local index, encoding and root files only; nothing is downloaded or written outside
tools/out.

    python3 -I tools/casc.py               # self-test: counts and a few known icons
    python3 -I tools/casc.py export 134120 # write tools/out/icons/134120.png
"""
import glob
import io
import os
import struct
import sys
import zlib

WOW = os.environ.get("WOW_ROOT", "/Applications/World of Warcraft")
DATA = WOW + "/Data"
HERE = os.path.dirname(os.path.abspath(__file__))
ICONS = HERE + "/out/icons"


def build_config(product):
    with open(WOW + "/.build.info") as f:
        lines = f.read().splitlines()
    head = [h.split("!")[0] for h in lines[0].split("|")]
    for ln in lines[1:]:
        row = dict(zip(head, ln.split("|")))
        if row.get("Product") == product:
            key = row["Build Key"]
            path = "%s/config/%s/%s/%s" % (DATA, key[:2], key[2:4], key)
            cfg = {}
            for l in open(path):
                if " = " in l:
                    k, v = l.strip().split(" = ", 1)
                    cfg[k] = v.split()
            return cfg
    raise SystemExit("no product " + product)


def load_index():
    best = {}
    for p in glob.glob(DATA + "/data/*.idx"):
        name = os.path.basename(p)
        bucket, ver = int(name[:2], 16), int(name[2:10], 16)
        if bucket not in best or ver > best[bucket][0]:
            best[bucket] = (ver, p)
    idx = {}
    for _, p in best.values():
        b = open(p, "rb").read()
        hsize = struct.unpack_from("<I", b, 0)[0]
        pos = (8 + hsize + 15) & ~15
        esize = struct.unpack_from("<I", b, pos)[0]
        pos += 8
        for i in range(esize // 18):
            e = b[pos + i * 18: pos + i * 18 + 18]
            key = e[:9]
            hi = e[9]
            lo = struct.unpack(">I", e[10:14])[0]
            packed = (hi << 32) | lo
            archive, offset = packed >> 30, packed & 0x3FFFFFFF
            size = struct.unpack("<I", e[14:18])[0]
            if key not in idx:
                idx[key] = (archive, offset, size)
    return idx


def blte(data):
    assert data[:4] == b"BLTE", data[:4]
    hsize = struct.unpack(">I", data[4:8])[0]
    out = []
    if hsize == 0:
        chunks = [(len(data) - 8, None)]
        pos = 8
    else:
        count = struct.unpack(">I", b"\0" + data[9:12])[0]
        chunks = []
        p = 12
        for _ in range(count):
            c, d = struct.unpack(">II", data[p:p + 8])
            chunks.append((c, d))
            p += 24
        pos = hsize
    for csize, _ in chunks:
        ch = data[pos:pos + csize]
        pos += csize
        mode = ch[:1]
        if mode == b"N":
            out.append(ch[1:])
        elif mode == b"Z":
            out.append(zlib.decompress(ch[1:]))
        elif mode == b"E":
            raise IOError("encrypted chunk")
        else:
            raise IOError("blte mode %r" % mode)
    return b"".join(out)


class Casc:
    def __init__(self, product="wowf"):
        self.cfg = build_config(product)
        self.idx = load_index()
        self.enc = self.load_encoding()
        self.root, self.names = self.load_root()

    def read_ekey(self, ekey):
        loc = self.idx.get(ekey[:9])
        if not loc:
            raise KeyError("not local")
        archive, offset, size = loc
        with open("%s/data/data.%03d" % (DATA, archive), "rb") as f:
            f.seek(offset)
            raw = f.read(size)
        return blte(raw[30:])

    def load_encoding(self):
        data = self.read_ekey(bytes.fromhex(self.cfg["encoding"][1]))
        assert data[:2] == b"EN"
        ck, ek = data[3], data[4]
        cpage = struct.unpack(">H", data[5:7])[0] * 1024
        cpages = struct.unpack(">I", data[9:13])[0]
        espec = struct.unpack(">I", data[18:22])[0]
        pos = 22 + espec + cpages * 32
        enc = {}
        for _ in range(cpages):
            p, end = pos, pos + cpage
            while p < end:
                n = data[p]
                if n == 0:
                    break
                ckey = data[p + 6:p + 6 + ck]
                enc[ckey] = data[p + 6 + ck:p + 6 + ck + ek]
                p += 6 + ck + ek * n
            pos = end
        return enc

    def load_root(self):
        data = self.read_ekey(self.enc[bytes.fromhex(self.cfg["root"][0])])
        assert data[:4] == b"TSFM", data[:4]
        a, b = struct.unpack_from("<II", data, 4)
        if a < 100:  # header size, newer layout
            hsize, version = a, b
            pos = hsize
        else:
            version, pos = 0, 12
        root, names = {}, {}
        while pos < len(data):
            n = struct.unpack_from("<I", data, pos)[0]
            if version >= 2:
                locale, f1, f2 = struct.unpack_from("<III", data, pos + 4)
                f3 = data[pos + 16]
                content = f1 | f2 | (f3 << 17)
                pos += 17
            else:
                content, locale = struct.unpack_from("<II", data, pos + 4)
                pos += 12
            deltas = struct.unpack_from("<%di" % n, data, pos)
            pos += 4 * n
            ckeys = [data[pos + 16 * i:pos + 16 * i + 16] for i in range(n)]
            pos += 16 * n
            hashes = None
            if not (content & 0x10000000):
                hashes = struct.unpack_from("<%dQ" % n, data, pos)
                pos += 8 * n
            fid = -1
            keep = (locale & 0x2) or locale == 0xFFFFFFFF or locale == 0
            for i in range(n):
                fid = fid + 1 + deltas[i]
                if keep and fid not in root:
                    root[fid] = ckeys[i]
                    if hashes:
                        names[hashes[i]] = fid
        return root, names

    def read_fid(self, fid):
        return self.read_ekey(self.enc[self.root[fid]])


def jenkins96(path):
    """hashlittle2 of the normalized path, as CASC root name hashes use."""
    s = path.upper().replace("/", "\\").encode()
    length = len(s)
    a = b = c = (0xDEADBEEF + length) & 0xFFFFFFFF
    M = 0xFFFFFFFF

    def rot(x, k):
        return ((x << k) | (x >> (32 - k))) & M

    i = 0
    while length > 12:
        a = (a + struct.unpack_from("<I", s, i)[0]) & M
        b = (b + struct.unpack_from("<I", s, i + 4)[0]) & M
        c = (c + struct.unpack_from("<I", s, i + 8)[0]) & M
        a = (a - c) & M; a ^= rot(c, 4); c = (c + b) & M
        b = (b - a) & M; b ^= rot(a, 6); a = (a + c) & M
        c = (c - b) & M; c ^= rot(b, 8); b = (b + a) & M
        a = (a - c) & M; a ^= rot(c, 16); c = (c + b) & M
        b = (b - a) & M; b ^= rot(a, 19); a = (a + c) & M
        c = (c - b) & M; c ^= rot(b, 4); b = (b + a) & M
        length -= 12
        i += 12
    if length == 0:
        return (c << 32) | b
    tail = s[i:] + b"\0" * (12 - length)
    a = (a + struct.unpack_from("<I", tail, 0)[0]) & M
    b = (b + struct.unpack_from("<I", tail, 4)[0]) & M
    c = (c + struct.unpack_from("<I", tail, 8)[0]) & M
    c ^= b; c = (c - rot(b, 14)) & M
    a ^= c; a = (a - rot(c, 11)) & M
    b ^= a; b = (b - rot(a, 25)) & M
    c ^= b; c = (c - rot(b, 16)) & M
    a ^= c; a = (a - rot(c, 4)) & M
    b ^= a; b = (b - rot(a, 14)) & M
    c ^= b; c = (c - rot(b, 24)) & M
    return (c << 32) | b


_casc = None


def icon_png(fid):
    """Path to a PNG of icon fileID `fid`, decoded from the client on first use."""
    global _casc
    path = "%s/%d.png" % (ICONS, fid)
    if not os.path.exists(path):
        from PIL import Image
        if _casc is None:
            _casc = Casc()
        os.makedirs(ICONS, exist_ok=True)
        Image.open(io.BytesIO(_casc.read_fid(fid))).convert("RGBA").save(path)
    return path


def icon_fid(casc, name):
    """fileID of Interface\\Icons\\<name>, or None if this build doesn't ship it."""
    return casc.names.get(jenkins96("Interface\\Icons\\" + name + ".blp"))


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "export":
        for a in sys.argv[2:]:
            print(icon_png(int(a)))
        sys.exit(0)
    c = Casc()
    print("index", len(c.idx), "encoding", len(c.enc), "root", len(c.root), "named", len(c.names))
    for name in ("inv_misc_gem_pearl_01", "inv_jewelcrafting_80_cutgem02_red", "inv_fishing_innards_pearlblack"):
        fid = icon_fid(c, name)
        print(name, fid, c.read_fid(fid)[:4] if fid else "missing")
