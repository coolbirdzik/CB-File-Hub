"""Render every app icon from cb_file_manager/assets/images/logo.svg.

Requires: pip install pillow resvg-py
Run from the repository root: python scripts/generate_app_icons.py
"""

from __future__ import annotations

from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw
import resvg_py


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "cb_file_manager"
SVG = APP / "assets/images/logo.svg"
BACKGROUND = "#F8F9FB"


def mark(size: int) -> Image.Image:
    return Image.open(
        BytesIO(resvg_py.svg_to_bytes(svg_path=str(SVG), width=size, height=size))
    ).convert("RGBA")


MASTER = mark(2160)


def composed(size: tuple[int, int], scale: float = 1.0, background=None) -> Image.Image:
    width, height = size
    canvas = Image.new("RGBA", size, background or (0, 0, 0, 0))
    side = round(min(width, height) * scale)
    art = MASTER.resize((side, side), Image.Resampling.LANCZOS)
    canvas.alpha_composite(art, ((width - side) // 2, (height - side) // 2))
    return canvas


def save(path: Path, size: tuple[int, int], scale=1.0, background=None, mode="RGBA"):
    path.parent.mkdir(parents=True, exist_ok=True)
    image = composed(size, scale, background)
    image.convert(mode).save(path, optimize=True)


def round_icon(size: int) -> Image.Image:
    image = composed((size, size), 0.86, BACKGROUND)
    mask = Image.new("L", (size, size))
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    image.putalpha(mask)
    return image


def circle_badge(size: tuple[int, int]) -> Image.Image:
    width, height = size
    # Draw at 2x so the white circular edge stays smooth in the MSIX package.
    canvas = Image.new("RGBA", (width * 2, height * 2))
    diameter = min(width, height) * 2
    left = (width * 2 - diameter) // 2
    top = (height * 2 - diameter) // 2
    ImageDraw.Draw(canvas).ellipse(
        (left, top, left + diameter - 1, top + diameter - 1), fill="#FFFFFF"
    )
    canvas.alpha_composite(composed(canvas.size, 0.88))
    return canvas.resize(size, Image.Resampling.LANCZOS)


assets = APP / "assets/images"
save(assets / "logo.png", (1024, 1024))
save(assets / "logo512.png", (512, 512))
save(assets / "logo2160.png", (2160, 2160))
save(assets / "logo1440.png", (1440, 2160), 0.72, "#FFFFFF")
circle_badge((756, 711)).save(assets / "logo_circle.png", optimize=True)

web = APP / "web"
save(web / "favicon.png", (16, 16), 1.0)
for side in (192, 512):
    save(web / f"icons/Icon-{side}.png", (side, side), 0.88, BACKGROUND, "RGB")
    save(web / f"icons/Icon-maskable-{side}.png", (side, side), 0.68, BACKGROUND)

windows_icon = APP / "windows/runner/resources/app_icon.ico"
composed((256, 256)).save(
    windows_icon,
    format="ICO",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

mac = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
for side in (16, 32, 64, 128, 256, 512, 1024):
    save(mac / f"app_icon_{side}.png", (side, side), 0.9)

ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for path in ios.glob("Icon-App-*.png"):
    with Image.open(path) as existing:
        size = existing.size
    save(path, size, 0.88, BACKGROUND, "RGB")

android = APP / "android/app/src"
for variant in ("main", "debug", "profile"):
    res = android / variant / "res"
    for density, side in (("ldpi", 36), ("mdpi", 48), ("hdpi", 72),
                          ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        folder = res / f"mipmap-{density}"
        if not folder.exists():
            continue
        save(folder / "ic_launcher.png", (side, side), 0.84, BACKGROUND)
        round_icon(side).save(folder / "ic_launcher_round.png", optimize=True)
        foreground = folder / "ic_launcher_foreground.png"
        if foreground.exists():
            save(foreground, (round(side * 2.25),) * 2, 0.69)

for name in ("ic_launcher-web.png", "playstore-icon.png"):
    save(android / "main/res" / name, (512, 512), 0.88, BACKGROUND)

website = ROOT / "website/public"
if website.exists():
    save(website / "logo.png", (512, 512))

print("Rendered app icons from", SVG)
