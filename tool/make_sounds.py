"""Klangsammlung von Scrivi bauen: assets/sounds/scrivi.sf2

Gitarren und Bässe stammen von FreePats, alle übrigen Instrumente und das
Schlagzeug aus FluidR3 Mono (MuseScore-Fassung). Alle Lizenzen passen zur
GPL (CC0, GPL mit Ausnahme, MIT), siehe assets/sounds/LIZENZEN.txt.

Aufruf (die Quellen vorher herunterladen und entpacken, siehe QUELLEN unten):
    python3 tool/make_sounds.py <Ordner mit den Quellen>

Braucht numpy und ffmpeg (zum Entpacken der SF3 und zum Umrechnen der
Abtastrate). Ergebnis: eine einzige SF2 mit je einem Preset pro Klangnummer
(General MIDI); Bank 128 ist das Schlagzeug.
"""

import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import sf2lib  # noqa: E402

# Quellen (Dateinamen relativ zum Quellordner)
QUELLEN = {
    'nylon': 'SpanishClassicalGuitar-SF2-20190618/SpanishClassicalGuitar-20190618.sf2',
    'steel': 'FSS-SteelStringGuitar-small-SF2-20200521/FSS-SteelStringGuitar-small-20200521.sf2',
    'jazz': 'EGuitarFSBS-jazz bridge small SF2-20260807/EGuitarFSBS-jazz bridge small 20260807.sf2',
    'clean': 'EGuitarFSBS-clean bridge small SF2-20260807/EGuitarFSBS-clean bridge small 20260807.sf2',
    'finger': 'FingerBassYR SF2-20190930/FingerBassYR 20190930.sf2',
    'pick': 'PickedBassYR SF2-20190930/PickedBassYR 20190930.sf2',
    'fluid': 'FluidR3Mono_GM.sf3',
}

# FreePats → Klangnummer (General MIDI)
FREEPATS = [('nylon', 24), ('steel', 25), ('jazz', 26), ('clean', 27), ('finger', 33), ('pick', 34)]

# Aus FluidR3: diese Klangnummern (Bank 0); die übrigen nimmt Scrivi aus derselben Familie
FLUID = [0, 4, 6, 11, 12, 16, 21, 22, 32, 35, 38, 40, 42, 46, 48, 52, 56, 57, 60, 61, 65, 66, 68, 71, 73,
         75, 80, 81, 88, 89, 105]
FLUID_DRUMS = [0]  # Bank 128

# Höchstens so lang (Sekunden); längere Samples klingen aus (Gitarren klingen von selbst ab)
MAX_SECONDS = {'nylon': 4.0, 'steel': 4.0, 'jazz': 4.0, 'clean': 4.0, 'finger': 4.0, 'pick': 4.0}
# Höchste Abtastrate
MAX_RATE = {'fluid': 32000}


def resample(pcm, rate, target):
    p = subprocess.run(
        ['ffmpeg', '-v', 'error', '-f', 's16le', '-ar', str(rate), '-ac', '1', '-i', 'pipe:0',
         '-af', f'aresample={target}', '-f', 's16le', '-ar', str(target), 'pipe:1'],
        input=pcm.astype('<i2').tobytes(), capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype='<i2').copy()


class Builder:
    def __init__(self):
        self.presets = []
        self.instruments = []
        self.samples = []

    def add(self, sf, preset, bank, program, key, name=None):
        """Preset [preset] aus [sf] mit seinen Instrumenten und Samples übernehmen."""
        sample_map = {}
        inst_map = {}
        loop_off = set()
        for pz in preset.zones:
            if pz.target in inst_map:
                continue
            inst = sf.instruments[pz.target]
            zones = []
            for iz in inst.zones:
                s = sf.samples[iz.target]
                if s.stype == 2:  # rechter Kanal: weglassen, der linke klingt mono
                    continue
                if iz.target not in sample_map:
                    sample_map[iz.target] = len(self.samples)
                    self.samples.append(self._prepare(s, key, loop_off, iz.target))
                g = dict(iz.gens)
                if s.stype == 4:
                    g.pop(sf2lib.GEN_PAN, None)
                if iz.target in loop_off:
                    g.pop(sf2lib.GEN_SAMPLE_MODES, None)
                zones.append(sf2lib.Zone(g, sample_map[iz.target]))
            inst_map[pz.target] = len(self.instruments)
            self.instruments.append(sf2lib.Instrument(inst.name, zones))
        zones = [sf2lib.Zone(dict(pz.gens), inst_map[pz.target]) for pz in preset.zones]
        self.presets.append(sf2lib.Preset(name or preset.name, bank, program, zones))

    def _prepare(self, s, key, loop_off, index):
        pcm, rate = s.pcm, s.rate
        ls, le = s.loop_start, min(s.loop_end, len(pcm))
        cap = MAX_RATE.get(key)
        if cap and rate > cap:
            k = cap / rate
            pcm = resample(pcm, rate, cap)
            ls, le = int(round(ls * k)), min(int(round(le * k)), len(pcm))
            rate = cap
        mx = MAX_SECONDS.get(key)
        if mx and len(pcm) > mx * rate:
            n = int(mx * rate)
            fade = int(0.6 * rate)
            pcm = pcm[:n].astype(np.float64)
            pcm[n - fade:] *= np.linspace(1, 0, fade) ** 2
            pcm = np.round(pcm).astype(np.int16)
            if le > n:
                loop_off.add(index)
                ls, le = 0, 0
        if le - ls < 8:
            ls, le = 0, 0
        return sf2lib.Sample(s.name, pcm, rate, s.root, s.corr, ls, le, 1)


def main(src):
    b = Builder()
    for key, program in FREEPATS:
        sf = sf2lib.read(os.path.join(src, QUELLEN[key]))
        b.add(sf, sf.presets[0], 0, program, key)
        print('FreePats', key, '→', program)
    fluid = sf2lib.read(os.path.join(src, QUELLEN['fluid']))
    by = {(p.bank, p.program): p for p in fluid.presets}
    for prog in FLUID:
        b.add(fluid, by[(0, prog)], 0, prog, 'fluid')
    for prog in FLUID_DRUMS:
        b.add(fluid, by[(128, prog)], 128, prog, 'fluid')
    b.presets.sort(key=lambda p: (p.bank, p.program))
    out = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds', 'scrivi.sf2')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sf2lib.write(out, b.presets, b.instruments, b.samples, info_name='Scrivi',
                 comment='FreePats (CC0, GPL) und FluidR3 Mono (MIT), siehe LIZENZEN.txt')
    total = sum(len(s.pcm) for s in b.samples) * 2 / 1e6
    print(f'{len(b.presets)} Klänge, {len(b.samples)} Samples, {total:.1f} MB → {os.path.normpath(out)}')


if __name__ == '__main__':
    main(sys.argv[1])
