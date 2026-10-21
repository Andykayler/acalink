#!/usr/bin/env python3
"""
Generates every Acalink icon and launch image from ONE drawing of the mark, so
the app icon, the web icons and the launch screens can never drift apart.

The mark is the same one the Acalink web app uses: a white graduation cap on the
brand blue. It is drawn here as polygons (in a 512-unit square) and rendered at
4x then scaled down, so edges are clean at every size.

Run from the acalink/ folder:   python3 tool/generate_icons.py
Needs Pillow (pip install pillow). Re-run it whenever the mark changes.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

# Brand blue, top-left to bottom-right — sampled from the web app's own icon.
BLUE_A = (77, 107, 243)
BLUE_B = (61, 89, 221)
NAVY = (13, 20, 39)          # #0D1427, the app's dark background
WHITE = (255, 255, 255)

# The cap, in 512-unit coordinates (same drawing as public/icons/icon-512.png).
TOP = [(62, 231), (256, 138), (450, 231), (256, 324)]
BODY = [(148, 283), (256, 338), (364, 283), (364, 358), (256, 410), (148, 358)]
TASSEL = [(438, 236), (454, 236), (454, 348), (438, 348)]
CAP_BOX = (62, 138, 454, 410)   # x0, y0, x1, y1 of the whole mark


def gradient(size):
    """Diagonal brand gradient, size x size, RGBA."""
    g = Image.new("RGB", (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(BLUE_A, BLUE_B))
    return g.convert("RGBA")


def cap_layer(size, width_fraction, colour=WHITE):
    """The cap alone, centred in a transparent size x size layer, `width_fraction` of its width."""
    x0, y0, x1, y1 = CAP_BOX
    scale = size * width_fraction / (x1 - x0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    big = 4
    layer = Image.new("RGBA", (size * big, size * big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for poly in (TOP, BODY, TASSEL):
        pts = [((px - cx) * scale + size / 2, (py - cy) * scale + size / 2) for px, py in poly]
        d.polygon([(x * big, y * big) for x, y in pts], fill=colour + (255,))
    return layer.resize((size, size), Image.LANCZOS)


def tile(size, rounded=True, cap=0.76):
    """Brand tile with the cap. Rounded corners for 'any' icons; full-bleed for masked ones."""
    big = max(size, 512)  # draw large enough that the gradient and corners are smooth
    img = gradient(big)
    if rounded:
        mask = Image.new("L", (big * 4, big * 4), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, big * 4 - 1, big * 4 - 1), radius=int(big * 4 * 0.2237), fill=255)
        img.putalpha(mask.resize((big, big), Image.LANCZOS))
    img.alpha_composite(cap_layer(big, cap))
    return img.resize((size, size), Image.LANCZOS)


def save(img, rel, flatten=False):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if flatten:  # iOS app icons must have no alpha channel
        bg = Image.new("RGB", img.size, BLUE_B)
        bg.paste(img, mask=img.split()[3])
        img = bg
    img.save(path)
    print("wrote", rel)


# ── Web ──────────────────────────────────────────────────────────────────────
save(tile(32), "web/favicon.png")
for n in (192, 512):
    save(tile(n), f"web/icons/Icon-{n}.png")
    save(tile(n, rounded=False, cap=0.60), f"web/icons/Icon-maskable-{n}.png")

# ── Android ──────────────────────────────────────────────────────────────────
for folder, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    save(tile(px), f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png")
# Adaptive icon (Android 8+): a 108dp canvas, cap inside the 66dp safe zone, on a flat brand background.
for folder, px in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)):
    save(cap_layer(px, 0.44), f"android/app/src/main/res/mipmap-{folder}/ic_launcher_foreground.png")
# The launch logo (shown on the dark launch background before Flutter draws).
save(tile(360), "android/app/src/main/res/drawable/launch_logo.png")

# ── iOS ──────────────────────────────────────────────────────────────────────
ios = {
    "20x20@1x": 20, "20x20@2x": 40, "20x20@3x": 60, "29x29@1x": 29, "29x29@2x": 58, "29x29@3x": 87,
    "40x40@1x": 40, "40x40@2x": 80, "40x40@3x": 120, "60x60@2x": 120, "60x60@3x": 180,
    "76x76@1x": 76, "76x76@2x": 152, "83.5x83.5@2x": 167, "1024x1024@1x": 1024,
}
for name, px in ios.items():
    save(tile(px, rounded=False, cap=0.62), f"ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{name}.png", flatten=True)
for scale, px in ((1, 168), (2, 336), (3, 504)):
    save(tile(px), "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage" + ("" if scale == 1 else f"@{scale}x") + ".png")

# ── macOS and Windows ────────────────────────────────────────────────────────
for px in (16, 32, 64, 128, 256, 512, 1024):
    save(tile(px), f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{px}.png")
ico = tile(256)
ico.save(ROOT / "windows/runner/resources/app_icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("wrote windows/runner/resources/app_icon.ico")
