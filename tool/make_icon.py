# Zeichnet das Scrivi-Symbol: Quadrat mit runden Ecken (aussen durchsichtig),
# Verlauf Pink → Violett wie Volti und Conti. Darin ein weisser Schwung – Federstrich
# und Bogen zugleich –, der einen schrägen Notenkopf umfängt.
# Aufruf: python3 tool/make_icon.py
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 1024          # Arbeitsgrösse
K = 3             # Überabtastung für glatte Kanten
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PINK, VIOLET = (240, 71, 156), (122, 60, 240)


def gradient():
    g = Image.new('RGBA', (S, S))
    px = g.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * (S - 1))
            px[x, y] = tuple(int(PINK[i] + (VIOLET[i] - PINK[i]) * t) for i in range(3)) + (255,)
    return g


def bez(p0, p1, p2, p3):
    """Kubische Kurve als Funktion von t (0..1)."""
    def f(t):
        u = 1 - t
        return (u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1])
    return f


def ribbon(d, f, wmax, a, b, skew, n=400):
    """Band entlang der Kurve f mit spitzen Enden: Breite t^a (1-t)^b, auf wmax
    normiert. skew legt die Breite mehr auf eine Seite (0 = beidseitig gleich)."""
    tm = a / (a + b)
    norm = tm**a * (1 - tm)**b
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        x, y = f(t)
        x2, y2 = f(min(1, t + 1e-3))
        x1, y1 = f(max(0, t - 1e-3))
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy) or 1
        nx, ny = -dy / length, dx / length
        w = wmax * (t**a * (1 - t)**b) / norm
        wl, wr = w * (1 + skew) / 2, w * (1 - skew) / 2
        left.append(((x + nx * wl) * K, (y + ny * wl) * K))
        right.append(((x - nx * wr) * K, (y - ny * wr) * K))
    d.polygon(left + right[::-1], fill=255)


def ellipse(d, cx, cy, rx, ry, rot):
    pts = []
    for i in range(160):
        t = 2 * math.pi * i / 160
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append(((cx + x * math.cos(rot) - y * math.sin(rot)) * K,
                    (cy + x * math.sin(rot) + y * math.cos(rot)) * K))
    d.polygon(pts, fill=255)


def mark():
    """Das Zeichen als Maske (weiss = Zeichen)."""
    img = Image.new('L', (S * K, S * K), 0)
    d = ImageDraw.Draw(img)
    # Der Schwung: links tief unten, oben herum nach rechts, spitz auslaufend
    ribbon(d, bez((260, 760), (200, 380), (560, 170), (820, 300)), 165, a=0.65, b=1.0, skew=0.6)
    # Der Notenkopf, leicht schräg wie gestochen
    ellipse(d, 575, 610, 128, 90, -0.42)
    # Kanten glätten: weichzeichnen und wieder scharf schneiden
    img = img.filter(ImageFilter.GaussianBlur(6)).point(lambda v: 255 if v >= 128 else 0)
    return img.resize((S, S), Image.LANCZOS)


def icon(size):
    rounded = Image.new('L', (S, S), 0)
    ImageDraw.Draw(rounded).rounded_rectangle([0, 0, S - 1, S - 1], radius=230, fill=255)
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    im.paste(gradient(), (0, 0), rounded)
    # weicher Glanz oben links
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-200, -260, 700, 560], fill=(255, 255, 255, 38))
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    im = Image.alpha_composite(im, Image.composite(glow, Image.new('RGBA', (S, S), (0, 0, 0, 0)), rounded))
    im = Image.composite(Image.new('RGBA', (S, S), (255, 255, 255, 255)), im, mark())
    return im.resize((size, size), Image.LANCZOS)


os.makedirs(os.path.join(base, 'assets/brand'), exist_ok=True)
big = icon(1024)
big.resize((512, 512), Image.LANCZOS).save(os.path.join(base, 'assets/brand/scrivi_icon.png'))
big.resize((256, 256), Image.LANCZOS).save(
    os.path.join(base, 'windows/runner/resources/app_icon.ico'),
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for name, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    big.resize((px, px), Image.LANCZOS).save(os.path.join(base, f'android/app/src/main/res/mipmap-{name}/ic_launcher.png'))
print('ok')
