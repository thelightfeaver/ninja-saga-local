#!/usr/bin/env python3
"""Neutralise AIR-only flash.filesystem classes in the Ninja Saga client.

Ruffle (the browser Flash emulator) does not implement Adobe AIR's
``flash.filesystem`` package.  The custom Ninja Saga client only uses those
classes for optional local-file caching (``id.ninjasage.Util.url`` and
``Storage.StoreAsset``); every URL the local server serves is absolute HTTP(S),
so those branches never execute.  However, AVM2 verifies the whole class when
it is first referenced, and the missing classes make the client abort with
Error #1014.

This script rewrites the QName entries for ``flash.filesystem.File``,
``FileStream`` and ``FileMode`` in the SWF's ABC constant pool to point at an
existing Flash Player class of the same encoded size.  Nothing else changes:
the ABC/Multiname table keeps its exact size, so no offsets need adjusting.

Usage:
    python3 tools/patch_air_stubs.py input.swf output.swf
"""
import struct
import sys
import zlib
import lzma


def read_u30(b, o):
    v = 0
    shift = 0
    while True:
        byte = b[o]
        o += 1
        v |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            return v, o
        shift += 7


def u30len(v):
    n = 1
    while v >= 0x80:
        v >>= 7
        n += 1
    return n


class ABCPool:
    def __init__(self, b, off):
        self.b = b
        self.off = off
        o = off
        self.minor, self.major = struct.unpack_from("<HH", b, o)
        o += 4
        n, o = read_u30(b, o)
        for _ in range(max(n - 1, 0)):
            _, o = read_u30(b, o)
        n, o = read_u30(b, o)
        for _ in range(max(n - 1, 0)):
            _, o = read_u30(b, o)
        n, o = read_u30(b, o)
        o += max(n - 1, 0) * 8

        self.strings = []
        n, o = read_u30(b, o)
        for _ in range(max(n - 1, 0)):
            ln, o = read_u30(b, o)
            start = o
            self.strings.append((start, ln, b[o:o + ln].decode("utf-8", "replace")))
            o += ln

        self.namespaces = []
        n, o = read_u30(b, o)
        for _ in range(max(n - 1, 0)):
            start = o
            kind = b[o]
            o += 1
            name, o = read_u30(b, o)
            self.namespaces.append((start, kind, name))

        n, o = read_u30(b, o)
        for _ in range(max(n - 1, 0)):
            cnt, o = read_u30(b, o)
            o += cnt * u30len(0) if False else 0
            for _ in range(cnt):
                _, o = read_u30(b, o)

        self.multinames = []
        n, o = read_u30(b, o)
        for _ in range(max(n - 1, 0)):
            start = o
            kind = b[o]
            o += 1
            info = {}
            if kind in (0x07, 0x0D):
                ns, o = read_u30(b, o)
                nm, o = read_u30(b, o)
                info = {"ns": ns, "name": nm}
            elif kind in (0x0F, 0x10):
                nm, o = read_u30(b, o)
                info = {"name": nm}
            elif kind in (0x11, 0x12):
                pass
            elif kind in (0x09, 0x0E):
                nm, o = read_u30(b, o)
                ns, o = read_u30(b, o)
                info = {"name": nm, "ns_set": ns}
            elif kind in (0x1B, 0x1C):
                ns, o = read_u30(b, o)
                info = {"ns_set": ns}
            elif kind == 0x1D:
                base, o = read_u30(b, o)
                cnt, o = read_u30(b, o)
                params = []
                for _ in range(cnt):
                    x, o = read_u30(b, o)
                    params.append(x)
                info = {"base": base, "params": params}
            else:
                raise ValueError("unknown multiname kind %#x at %#x" % (kind, start))
            self.multinames.append((start, kind, info, b[start:o]))
        self.cp_end = o

    def string(self, idx):
        return self.strings[idx - 1][2] if 0 < idx <= len(self.strings) else None

    def namespace(self, idx):
        if not (0 < idx <= len(self.namespaces)):
            return None
        _, kind, name = self.namespaces[idx - 1]
        return kind, self.string(name)

    def qname(self, m):
        start, kind, info, raw = m
        if kind not in (0x07, 0x0D):
            return None
        ns = self.namespace(info["ns"])
        name = self.string(info["name"])
        return (ns[1] if ns else None), name


def find_abc_tags(body):
    nbits = body[0] >> 3
    total = 5 + 4 * nbits
    o = (total + 7) // 8
    o += 4
    tags = []
    while o + 2 <= len(body):
        code = struct.unpack_from("<H", body, o)[0]
        o += 2
        num, length = code >> 6, code & 0x3F
        if length == 0x3F:
            length = struct.unpack_from("<I", body, o)[0]
            o += 4
        if num in (72, 82):
            tags.append((num, o, length))
        o += length
    return tags


def decompress(data):
    if data[:3] == b"FWS":
        return data[8:], 0
    if data[:3] == b"CWS":
        return zlib.decompress(data[8:]), 1
    if data[:3] == b"ZWS":
        clen = struct.unpack("<I", data[8:12])[0]
        props = data[12:17]
        pb = props[0]
        lc, lp, pb2 = pb % 9, (pb // 9) % 5, pb // 45
        ds = int.from_bytes(props[1:5], "little")
        body = lzma.decompress(
            data[17:],
            format=lzma.FORMAT_RAW,
            filters=[{"id": lzma.FILTER_LZMA1, "dict_size": ds, "lc": lc, "lp": lp, "pb": pb2}],
        )
        return body, 2
    raise SystemExit("Unsupported SWF signature")


def compress(body, version, kind):
    if kind == 0:
        return b"FWS" + bytes([version]) + struct.pack("<I", len(body) + 8) + body
    # Always write zlib-compressed CWS; Ruffle understands it and it keeps
    # the patched SWF comfortably small.
    comp = zlib.compress(body, 9)
    return b"CWS" + bytes([version]) + struct.pack("<I", len(body) + 8) + comp


def main(src, dst):
    data = open(src, "rb").read()
    version = data[3]
    body, kind = decompress(data)
    body = bytearray(body)

    abc_tags = find_abc_tags(body)
    if not abc_tags:
        raise SystemExit("No DoABC tag found")

    targets = ["File", "FileStream", "FileMode"]
    replacements = []
    for _num, off, length in abc_tags:
        # DoABC: flags(u32) + name(c-string) + abc
        nend = body.index(b"\x00", off + 4)
        abc_off = nend + 1
        pool = ABCPool(body, abc_off)
        print(
            "ABC @%#x: %d strings, %d namespaces, %d multinames"
            % (abc_off, len(pool.strings), len(pool.namespaces), len(pool.multinames))
        )

        # Index the flash.filesystem package namespace.
        fs_ns = set()
        for idx, (_start, _kind, name_idx) in enumerate(pool.namespaces, start=1):
            if pool.string(name_idx) == "flash.filesystem":
                fs_ns.add(idx)

        # Find safe, same-size QNames to use as stand-ins.  Sprite/Bitmap/Loader
        # are guaranteed to exist in Ruffle and the client never executes the
        # AIR file-cache branches when served over HTTP.
        safe = {}
        for m in pool.multinames:
            q = pool.qname(m)
            if not q:
                continue
            uri, name = q
            if uri in ("flash.display", "flash.events", "flash.net", "flash.utils") and name in (
                "Sprite", "Bitmap", "Loader", "MovieClip", "Shape", "EventDispatcher",
                "URLRequest", "URLLoader", "ByteArray", "Dictionary",
            ):
                safe.setdefault(len(m[3]), []).append((q, m[3]))

        used = set()
        for target in targets:
            for m in pool.multinames:
                start, kind, info, raw = m
                if kind not in (0x07, 0x0D):
                    continue
                if info.get("ns") not in fs_ns or pool.string(info["name"]) != target:
                    continue
                candidates = safe.get(len(raw), [])
                chosen = None
                for q, r in candidates:
                    if q[1] not in used:
                        chosen = (q, r)
                        break
                if chosen is None and candidates:
                    chosen = candidates[0]
                if chosen is None:
                    raise SystemExit(
                        "No same-size safe QName for %s (raw len %d)" % (target, len(raw))
                    )
                q, r = chosen
                used.add(q[1])
                print(
                    "  patch %s at %#x (%s::%s, %d bytes) -> %s::%s"
                    % (target, start, "flash.filesystem", target, len(raw), q[0], q[1])
                )
                body[start:start + len(raw)] = r
                replacements.append(target)

    if not replacements:
        raise SystemExit("No flash.filesystem QNames found; nothing patched")

    out = compress(bytes(body), version, kind)
    open(dst, "wb").write(out)
    print("Wrote %s (%d bytes, %d replacements)" % (dst, len(out), len(replacements)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
