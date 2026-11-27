"""SoundFont-Dateien (SF2, SF3) lesen und eine eigene SF2 schreiben.

Nur was Scrivi braucht: Presets, Instrumente, Zonen mit ihren Generatoren
und die Samples. Modulatoren werden nicht übernommen (die Grundwerte
gelten). SF3 (Samples als Ogg Vorbis) wird mit ffmpeg entpackt.
"""

import struct
import subprocess

import numpy as np

GEN_INSTRUMENT = 41
GEN_KEY_RANGE = 43
GEN_VEL_RANGE = 44
GEN_PAN = 17
GEN_SAMPLE_ID = 53
GEN_SAMPLE_MODES = 54
GEN_OVERRIDING_ROOT = 58
# Generatoren, die nur in Instrument-Zonen erlaubt sind (Adress-Offsets usw.)
INST_ONLY = {0, 1, 2, 3, 4, 12, 45, 46, 47, 50, 54, 57, 58}


class Sample:
    def __init__(self, name, pcm, rate, root, corr, loop_start, loop_end, stype):
        self.name = name
        self.pcm = pcm  # np.int16, mono
        self.rate = rate
        self.root = root
        self.corr = corr
        self.loop_start = loop_start  # relativ zum Anfang des Samples
        self.loop_end = loop_end
        self.stype = stype  # 1 mono, 2 rechts, 4 links


class Zone:
    def __init__(self, gens, target):
        self.gens = gens  # dict oper -> roher 16-Bit-Wert (unsigned)
        self.target = target  # Index Instrument bzw. Sample


class Instrument:
    def __init__(self, name, zones):
        self.name = name
        self.zones = zones


class Preset:
    def __init__(self, name, bank, program, zones):
        self.name = name
        self.bank = bank
        self.program = program
        self.zones = zones


class SoundFont:
    def __init__(self):
        self.presets = []
        self.instruments = []
        self.samples = []


def _chunks(data, start, end):
    pos = start
    while pos + 8 <= end:
        cid = data[pos:pos + 4].decode('latin-1')
        size = struct.unpack_from('<I', data, pos + 4)[0]
        yield cid, pos + 8, size
        nxt = pos + 8 + size
        # Ungerade Grösse: eigentlich mit Füllbyte, manche Dateien lassen es weg
        if size & 1 and data[nxt:nxt + 4] not in (b'LIST', b'smpl', b'sm24', b'phdr'):
            nxt += 1
        pos = nxt


def _name(b):
    return b.split(b'\0', 1)[0].decode('latin-1').strip()


def _decode_ogg(blob):
    p = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', 'pipe:0', '-f', 's16le', '-ac', '1', 'pipe:1'],
        input=blob, capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype='<i2').copy()


def read(path):
    data = open(path, 'rb').read()
    assert data[0:4] == b'RIFF' and data[8:12] == b'sfbk', path
    lists = {}
    for cid, off, size in _chunks(data, 12, len(data)):
        if cid == 'LIST':
            lists[data[off:off + 4].decode()] = (off + 4, off + size)
    smpl = None
    for cid, off, size in _chunks(data, *lists['sdta']):
        if cid == 'smpl':
            smpl = (off, size)
    pd = {}
    for cid, off, size in _chunks(data, *lists['pdta']):
        pd[cid] = data[off:off + size]

    def recs(cid, fmt):
        sz = struct.calcsize(fmt)
        raw = pd[cid]
        return [struct.unpack_from(fmt, raw, i * sz) for i in range(len(raw) // sz)]

    phdr = recs('phdr', '<20sHHHIII')
    pbag = recs('pbag', '<HH')
    pgen = recs('pgen', '<HH')
    inst = recs('inst', '<20sH')
    ibag = recs('ibag', '<HH')
    igen = recs('igen', '<HH')
    shdr = recs('shdr', '<20sIIIIIBbHH')

    def zones(bag_from, bag_to, bags, gens, terminal):
        out = []
        glob = {}
        for b in range(bag_from, bag_to):
            g0, g1 = bags[b][0], bags[b + 1][0]
            gd = {}
            target = None
            for op, amt in gens[g0:g1]:
                if op == terminal:
                    target = amt
                else:
                    gd[op] = amt
            if target is None:
                if b == bag_from:
                    glob = gd
                continue
            merged = dict(glob)
            merged.update(gd)
            out.append(Zone(merged, target))
        return out

    sf = SoundFont()
    sm_off, sm_size = smpl
    for i in range(len(shdr) - 1):
        name, start, end, ls, le, rate, root, corr, link, stype = shdr[i]
        if stype & 0x8000:
            continue  # ROM-Samples gibt es hier nicht
        if stype & 0x10:  # SF3: Ogg Vorbis, start/end in Bytes
            pcm = _decode_ogg(data[sm_off + start:sm_off + end])
            lstart, lend = ls, le
        else:
            raw = data[sm_off + start * 2:sm_off + end * 2]
            pcm = np.frombuffer(raw, dtype='<i2').copy()
            lstart, lend = ls - start, le - start
        sf.samples.append(Sample(_name(name), pcm, rate, root, corr, lstart, lend, stype & 0x0F))
    for i in range(len(inst) - 1):
        sf.instruments.append(Instrument(_name(inst[i][0]), zones(inst[i][1], inst[i + 1][1], ibag, igen, GEN_SAMPLE_ID)))
    for i in range(len(phdr) - 1):
        name, prog, bank, bag = phdr[i][0], phdr[i][1], phdr[i][2], phdr[i][3]
        sf.presets.append(Preset(_name(name), bank, prog, zones(bag, phdr[i + 1][3], pbag, pgen, GEN_INSTRUMENT)))
    return sf


def s16(v):
    return v - 0x10000 if v >= 0x8000 else v


def write(path, presets, instruments, samples, info_name='Scrivi', comment=''):
    """Schreibt eine SF2 mit den gegebenen Listen (Zonen verweisen per Index)."""
    # Samples hintereinander, je 46 Nullen dazwischen
    parts = []
    shdr = b''
    pos = 0
    for s in samples:
        n = len(s.pcm)
        parts.append(s.pcm.astype('<i2').tobytes())
        parts.append(b'\0' * 92)
        ls = pos + max(0, min(s.loop_start, n - 1))
        le = pos + max(0, min(s.loop_end, n))
        shdr += struct.pack('<20sIIIIIBbHH', s.name.encode('latin-1')[:19], pos, pos + n, ls, le,
                            s.rate, s.root, s.corr, 0, 1)
        pos += n + 46
    shdr += struct.pack('<20sIIIIIBbHH', b'EOS', 0, 0, 0, 0, 0, 0, 0, 0, 0)
    smpl = b''.join(parts)

    def gen_bytes(gens, terminal_op, target):
        out = b''
        order = []
        if GEN_KEY_RANGE in gens:
            order.append(GEN_KEY_RANGE)
        if GEN_VEL_RANGE in gens:
            order.append(GEN_VEL_RANGE)
        order += [op for op in sorted(gens) if op not in (GEN_KEY_RANGE, GEN_VEL_RANGE)]
        for op in order:
            out += struct.pack('<HH', op, gens[op] & 0xFFFF)
        out += struct.pack('<HH', terminal_op, target)
        return out, len(order) + 1

    def hydra(items, terminal, is_preset):
        hdr = b''
        bags = b''
        gens = b''
        gi = 0
        bi = 0
        for it in items:
            if is_preset:
                hdr += struct.pack('<20sHHHIII', it.name.encode('latin-1')[:19], it.program, it.bank, bi, 0, 0, 0)
            else:
                hdr += struct.pack('<20sH', it.name.encode('latin-1')[:19], bi)
            for z in it.zones:
                bags += struct.pack('<HH', gi, 0)
                b, n = gen_bytes(z.gens, terminal, z.target)
                gens += b
                gi += n
                bi += 1
        if is_preset:
            hdr += struct.pack('<20sHHHIII', b'EOP', 0, 0, bi, 0, 0, 0)
        else:
            hdr += struct.pack('<20sH', b'EOI', bi)
        bags += struct.pack('<HH', gi, 0)
        gens += struct.pack('<HH', 0, 0)
        mods = b'\0' * 10
        return hdr, bags, mods, gens

    phdr, pbag, pmod, pgen = hydra(presets, GEN_INSTRUMENT, True)
    inst, ibag, imod, igen = hydra(instruments, GEN_SAMPLE_ID, False)

    def chunk(cid, payload):
        pad = b'\0' if len(payload) & 1 else b''
        return cid.encode() + struct.pack('<I', len(payload)) + payload + pad

    def lst(kind, payload):
        return chunk('LIST', kind.encode() + payload)

    def zstr(s):
        b = s.encode('latin-1') + b'\0'
        return b + (b'\0' if len(b) & 1 else b'')

    info = lst('INFO', chunk('ifil', struct.pack('<HH', 2, 1)) + chunk('isng', zstr('EMU8000')) +
               chunk('INAM', zstr(info_name)) + (chunk('ICMT', zstr(comment)) if comment else b''))
    sdta = lst('sdta', chunk('smpl', smpl))
    pdta = lst('pdta', chunk('phdr', phdr) + chunk('pbag', pbag) + chunk('pmod', pmod) + chunk('pgen', pgen) +
               chunk('inst', inst) + chunk('ibag', ibag) + chunk('imod', imod) + chunk('igen', igen) +
               chunk('shdr', shdr))
    body = b'sfbk' + info + sdta + pdta
    with open(path, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', len(body)) + body)
