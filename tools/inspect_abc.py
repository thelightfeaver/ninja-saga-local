#!/usr/bin/env python3
"""Inspect SWF DoABC constant pools and locate AIR-only class references.

Read-only helper used to plan the flash.filesystem workaround for Ruffle.
"""
import struct, sys

def read_u30(b, o):
    v = 0
    shift = 0
    while True:
        byte = b[o]; o += 1
        v |= (byte & 0x7f) << shift
        if not (byte & 0x80):
            return v, o
        shift += 7

def u30len(v):
    n = 1
    while v >= 0x80:
        v >>= 7; n += 1
    return n

class ABC:
    def __init__(self, b, off, size):
        self.b = b; self.off = off; self.size = size
        o = off
        self.minor, self.major = struct.unpack_from('<HH', b, o); o += 4
        # ints
        n, o = read_u30(b, o); o += (n - 1) * u30len(0) if False else 0
        # need to read each int properly
        o = off + 4
        n, o = read_u30(b, o)
        for _ in range(max(n-1, 0)):
            _, o = read_u30(b, o)
        n, o = read_u30(b, o)
        for _ in range(max(n-1, 0)):
            _, o = read_u30(b, o)
        n, o = read_u30(b, o); o += max(n-1, 0) * 8
        self.strings = []
        n, o = read_u30(b, o)
        for i in range(max(n-1, 0)):
            ln, o = read_u30(b, o)
            start = o
            val = b[o:o+ln].decode('utf-8', 'replace'); o += ln
            self.strings.append((start, ln, val))
        self.namespaces = []
        n, o = read_u30(b, o)
        for i in range(max(n-1, 0)):
            start = o
            kind = b[o]; o += 1
            name, o = read_u30(b, o)
            self.namespaces.append((start, kind, name))
        self.ns_sets = []
        n, o = read_u30(b, o)
        for i in range(max(n-1, 0)):
            cnt, o = read_u30(b, o)
            sets = []
            for _ in range(cnt):
                x, o = read_u30(b, o); sets.append(x)
            self.ns_sets.append(sets)
        self.multinames = []
        n, o = read_u30(b, o)
        for i in range(max(n-1, 0)):
            start = o
            kind = b[o]; o += 1
            info = {}
            if kind in (0x07, 0x0D):
                ns, o = read_u30(b, o); nm, o = read_u30(b, o)
                info = {'ns': ns, 'name': nm}
            elif kind in (0x0F, 0x10):
                nm, o = read_u30(b, o); info = {'name': nm}
            elif kind in (0x11, 0x12):
                pass
            elif kind in (0x09, 0x0E):
                nm, o = read_u30(b, o); ns, o = read_u30(b, o)
                info = {'name': nm, 'ns_set': ns}
            elif kind in (0x1B, 0x1C):
                ns, o = read_u30(b, o); info = {'ns_set': ns}
            elif kind == 0x1D:
                base, o = read_u30(b, o); cnt, o = read_u30(b, o)
                params = []
                for _ in range(cnt):
                    x, o = read_u30(b, o); params.append(x)
                info = {'base': base, 'params': params}
            else:
                raise ValueError(f'unknown multiname kind {kind:#x} at {start}')
            self.multinames.append((start, kind, info, b[start:o]))
        self.after_cp = o
        print(f"ABC @{off:#x} size={size} version={self.major}.{self.minor} strings={len(self.strings)} namespaces={len(self.namespaces)} multinames={len(self.multinames)} cp_end={o:#x}")

def find_abc_tags(body):
    b = body
    # skip frame header
    nbits = b[0] >> 3
    total = 5 + 4 * nbits
    o = (total + 7) // 8
    o += 4  # frame rate + count
    tags = []
    while o + 2 <= len(b):
        code = struct.unpack_from('<H', b, o)[0]; o += 2
        num, length = code >> 6, code & 0x3f
        if length == 0x3f:
            length = struct.unpack_from('<I', b, o)[0]; o += 4
        data_off = o
        if num in (72, 82):
            tags.append((num, data_off, length))
        o += length
    return tags

def main(path):
    data = open(path, 'rb').read()
    if data[:3] == b'CWS':
        import zlib; body = zlib.decompress(data[8:])
    elif data[:3] == b'FWS':
        body = data[8:]
    else:
        raise SystemExit('Only CWS/FWS supported; convert ZWS first')
    tags = find_abc_tags(body)
    print(path, 'abc tags:', tags)
    for num, off, length in tags:
        # flags u32 + name c-string
        flags = struct.unpack_from('<I', body, off)[0]
        nend = body.index(b'\x00', off + 4)
        name = body[off+4:nend].decode('latin1')
        abc_off = nend + 1
        print(f"DoABC tag={num} flags={flags} name={name!r} abc_off={abc_off:#x} abc_len={off+length-abc_off}")
        abc = ABC(body, abc_off, off+length-abc_off)
        # dump target refs
        def s(idx):
            return abc.strings[idx-1][2] if 0 < idx <= len(abc.strings) else f'<str {idx}>'
        def nss(idx):
            return abc.namespaces[idx-1] if 0 < idx <= len(abc.namespaces) else None
        targets = {'flash.filesystem', 'File', 'FileStream', 'FileMode'}
        for i, st in enumerate(abc.strings):
            if st[2] in targets:
                print(f"  str #{i+1} @{st[0]:#x} len={st[1]} {st[2]!r}")
        nsidx = {}
        for i, ns in enumerate(abc.namespaces):
            if 0 < ns[2] <= len(abc.strings):
                uri = abc.strings[ns[2]-1][2]
                if uri.startswith('flash.filesystem'):
                    nsidx[i+1] = uri
                    print(f"  ns #{i+1} @{ns[0]:#x} kind={ns[1]:#x} uri={uri!r}")
        for i, (start, kind, info, raw) in enumerate(abc.multinames):
            if kind in (7, 13) and info.get('ns') in nsidx:
                print(f"  multiname #{i+1} @{start:#x} kind={kind:#x} ns={info['ns']}({nsidx[info['ns']]}) name={s(info['name'])!r} rawlen={len(raw)}")
        # also print any qname whose name is File
        for i, (start, kind, info, raw) in enumerate(abc.multinames):
            if kind in (7, 13) and s(info.get('name', 0)) in ('File', 'FileStream', 'FileMode'):
                ns = nss(info.get('ns', 0))
                uri = s(ns[2]) if ns else '?'
                print(f"  file-name QName #{i+1} @{start:#x} kind={kind:#x} uri={uri!r} name={s(info['name'])!r} rawlen={len(raw)}")

if __name__ == '__main__':
    main(sys.argv[1])
