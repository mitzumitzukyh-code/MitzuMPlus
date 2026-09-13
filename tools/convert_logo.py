"""Convert the MitzuMPlus logo source image into WoW-ready textures.

    python tools/convert_logo.py [source.png]

Source (kept out of the runtime package): docs/assets/logo/mitzu_logo_source.png
Output (runtime, inside the addon):
    MitzuMPlus/Media/Icons/logo_64.tga   addon list (## IconTexture), minimap button,
                                          main window title bar and Coach HUD

Format written by hand to match the textures already shipped with the addon:
TGA type 2 (uncompressed true-color), 32 bpp BGRA, bottom-left origin
(image descriptor 0x08 = 8 alpha bits). Power-of-two sizes, as WoW requires.

The crop is a square centred on the visible emblem (bright-pixel bounding box)
with a small margin, so the M+ stays legible at 16-28 px.
"""

import struct
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "docs" / "assets" / "logo" / "mitzu_logo_source.png"
OUT_DIR = ROOT / "MitzuMPlus" / "Media" / "Icons"
SIZES = {"logo_64.tga": 64}
MARGIN = 0.07


def emblem_square(img: Image.Image) -> tuple[int, int, int, int]:
    lum = img.convert("RGB").convert("L").point(lambda v: 255 if v > 60 else 0)
    left, top, right, bottom = lum.getbbox()
    cx, cy = (left + right) / 2, (top + bottom) / 2
    half = max(right - left, bottom - top) * (1 + 2 * MARGIN) / 2
    box = [cx - half, cy - half, cx + half, cy + half]
    # Keep the square inside the image.
    w, h = img.size
    dx = max(0, -box[0]) - max(0, box[2] - w)
    dy = max(0, -box[1]) - max(0, box[3] - h)
    box = [box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy]
    return tuple(int(round(v)) for v in box)


def write_tga(img: Image.Image, path: Path) -> None:
    img = img.convert("RGBA")
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    rows = []
    px = img.load()
    for y in range(h - 1, -1, -1):  # bottom-left origin
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    path.write_bytes(header + b"".join(rows))


def main() -> None:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    img = Image.open(source).convert("RGBA")
    box = emblem_square(img)
    square = img.crop(box)
    for name, size in SIZES.items():
        out = square.resize((size, size), Image.LANCZOS)
        if size <= 64:
            out = out.filter(ImageFilter.UnsharpMask(radius=0.8, percent=60, threshold=2))
        write_tga(out, OUT_DIR / name)
        print(f"{name}: {size}x{size} from crop {box}")


if __name__ == "__main__":
    main()
