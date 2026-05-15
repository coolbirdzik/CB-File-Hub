#!/usr/bin/env python3
"""Generate promotional images from app screenshots."""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DESKTOP_SOURCE = ROOT / "screenshots" / "auto" / "desktop"
DEFAULT_MOBILE_SOURCE = ROOT / "screenshots"
DEFAULT_OUTPUT = ROOT / "screenshots" / "promo"

DESKTOP_SIZE = (2400, 1350)
MOBILE_SIZE = (1440, 2560)


@dataclass(frozen=True)
class PromoSpec:
    stem: str
    title: str
    subtitle: str
    accent: tuple[int, int, int]


DESKTOP_SPECS = [
    PromoSpec("file_browser", "Browse every workspace", "Local files, tabs, tags, and rich previews in one focused desktop view.", (54, 166, 255)),
    PromoSpec("gallery_hub", "Gallery built for large libraries", "Scan albums, media folders, and visual collections without losing context.", (250, 169, 64)),
    PromoSpec("album_detail", "Fast media detail views", "Open albums and keep browsing with responsive thumbnail grids.", (75, 204, 143)),
    PromoSpec("ai_search", "AI-assisted search", "Find, review, and act on files with an integrated assistant side panel.", (138, 112, 255)),
    PromoSpec("ai_approval", "Stay in control", "Review assistant actions before anything changes in your files.", (255, 107, 107)),
    PromoSpec("ai_conversation", "Ask about your files", "Keep a file-aware conversation beside the workspace you are using.", (102, 217, 232)),
    PromoSpec("tag_management", "Tag and organize", "Build lightweight systems for projects, references, and media collections.", (255, 214, 102)),
    PromoSpec("tagged_files", "Bring tagged files together", "Jump from tags to the exact files that matter right now.", (92, 219, 149)),
]

MOBILE_SPECS = [
    PromoSpec("mobile_home", "Your file hub on mobile", "Browse and organize files with a touch-first layout.", (54, 166, 255)),
    PromoSpec("mobile_grid", "Large libraries, still fast", "File grids stay clean and scannable on small screens.", (250, 169, 64)),
    PromoSpec("mobile_tabs", "Tabs that travel with you", "Switch views without losing your place.", (138, 112, 255)),
    PromoSpec("mobile_tags", "Tags on the go", "Group files into workflows wherever you are.", (92, 219, 149)),
]

DESKTOP_SPECS_VI = [
    PromoSpec("duyet_tap_tin", "Duyệt mọi thư mục", "Tập tin cục bộ, tab, tag và xem trước nhanh trong một không gian gọn gàng.", (54, 166, 255)),
    PromoSpec("thu_vien_anh", "Thư viện lớn vẫn dễ xem", "Quét album, thư mục media và bộ sưu tập hình ảnh mà không mất ngữ cảnh.", (250, 169, 64)),
    PromoSpec("chi_tiet_album", "Xem album nhanh", "Mở album và tiếp tục duyệt với lưới thumbnail phản hồi tốt.", (75, 204, 143)),
    PromoSpec("tim_kiem_ai", "Tìm kiếm với AI", "Tìm, xem lại và thao tác với tập tin bằng bảng trợ lý tích hợp.", (138, 112, 255)),
    PromoSpec("duyet_thao_tac_ai", "Luôn có quyền kiểm soát", "Xem lại hành động của trợ lý trước khi bất kỳ thay đổi nào diễn ra.", (255, 107, 107)),
    PromoSpec("hoi_dap_ai", "Hỏi về tập tin của bạn", "Trò chuyện với trợ lý hiểu ngữ cảnh ngay bên cạnh workspace.", (102, 217, 232)),
    PromoSpec("quan_ly_tag", "Gắn tag để sắp xếp", "Tạo hệ thống nhẹ cho dự án, tài liệu tham khảo và bộ sưu tập media.", (255, 214, 102)),
    PromoSpec("tap_tin_theo_tag", "Tập hợp tập tin theo tag", "Đi thẳng từ tag đến đúng những tập tin bạn cần lúc này.", (92, 219, 149)),
]

MOBILE_SPECS_VI = [
    PromoSpec("mobile_trang_chu", "File hub trên điện thoại", "Duyệt và sắp xếp tập tin với giao diện tối ưu cho cảm ứng.", (54, 166, 255)),
    PromoSpec("mobile_luoi_file", "Thư viện lớn vẫn nhanh", "Lưới tập tin vẫn gọn gàng và dễ quét trên màn hình nhỏ.", (250, 169, 64)),
    PromoSpec("mobile_tab", "Tab đi cùng bạn", "Chuyển qua lại giữa các chế độ xem mà không mất vị trí đang duyệt.", (138, 112, 255)),
    PromoSpec("mobile_tag", "Gắn tag mọi nơi", "Gom tập tin thành các workflow rõ ràng ngay trên điện thoại.", (92, 219, 149)),
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def cover_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    width, height = image.size
    target_width, target_height = size
    scale = max(target_width / width, target_height / height)
    resized = image.resize((round(width * scale), round(height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - target_width) // 2
    top = (resized.height - target_height) // 2
    return resized.crop((left, top, left + target_width, top + target_height))


def contain_resize(image: Image.Image, max_size: tuple[int, int]) -> Image.Image:
    image = image.copy()
    image.thumbnail(max_size, Image.Resampling.LANCZOS)
    return image


def rounded_rectangle_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def paste_rounded(base: Image.Image, image: Image.Image, xy: tuple[int, int], radius: int) -> None:
    mask = rounded_rectangle_mask(image.size, radius)
    base.paste(image.convert("RGBA"), xy, mask)


def draw_shadow(base: Image.Image, box: tuple[int, int, int, int], radius: int, blur: int, opacity: int) -> None:
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle(box, radius=radius, fill=(0, 0, 0, opacity))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(shadow)


def create_background(size: tuple[int, int], accent: tuple[int, int, int]) -> Image.Image:
    width, height = size
    top = (11, 18, 32)
    bottom = (18, 31, 48)
    image = Image.new("RGBA", size)
    pixels = image.load()
    for y in range(height):
        t = y / max(1, height - 1)
        wave = (math.sin(t * math.pi * 2.2) + 1) * 0.03
        for x in range(width):
            radial = 1 - min(1, math.dist((x / width, y / height), (0.68, 0.24)) / 0.82)
            mix = min(1, max(0, t + wave))
            r = round(top[0] * (1 - mix) + bottom[0] * mix + accent[0] * radial * 0.20)
            g = round(top[1] * (1 - mix) + bottom[1] * mix + accent[1] * radial * 0.20)
            b = round(top[2] * (1 - mix) + bottom[2] * mix + accent[2] * radial * 0.20)
            pixels[x, y] = (r, g, b, 255)

    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for i in range(10):
        x = round(width * (0.04 + i * 0.105))
        color = (*accent, 18 if i % 2 == 0 else 10)
        draw.line((x, height * 0.04, x + width * 0.28, height * 0.96), fill=color, width=2)
    return Image.alpha_composite(image, overlay)


def draw_text_block(draw: ImageDraw.ImageDraw, xy: tuple[int, int], title: str, subtitle: str, width: int, title_size: int) -> None:
    title_font = load_font(title_size, bold=True)
    subtitle_font = load_font(round(title_size * 0.34))
    eyebrow_font = load_font(round(title_size * 0.24), bold=True)
    x, y = xy
    draw.text((x, y), "CB FILE HUB", font=eyebrow_font, fill=(147, 197, 253, 255))
    y += round(title_size * 0.50)
    title_text = wrap_text(title, title_font, width)
    title_spacing = round(title_size * 0.16)
    draw.multiline_text((x, y), title_text, font=title_font, fill=(248, 250, 252, 255), spacing=title_spacing)
    title_bbox = draw.multiline_textbbox((x, y), title_text, font=title_font, spacing=title_spacing)
    y = title_bbox[3] + round(title_size * 0.32)
    draw.multiline_text((x, y), wrap_text(subtitle, subtitle_font, width), font=subtitle_font, fill=(203, 213, 225, 255), spacing=10)


def wrap_text(text: str, font: ImageFont.ImageFont, max_width: int) -> str:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if font.getlength(candidate) <= max_width:
            current = candidate
            continue
        if current:
            lines.append(current)
        current = word
    if current:
        lines.append(current)
    return "\n".join(lines)


def draw_desktop_frame(base: Image.Image, screenshot: Image.Image, spec: PromoSpec) -> None:
    frame_x, frame_y = 760, 260
    frame_w, frame_h = 1490, 820
    chrome_h = 58
    draw_shadow(base, (frame_x - 28, frame_y - 18, frame_x + frame_w + 28, frame_y + frame_h + 42), 44, 38, 150)
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((frame_x, frame_y, frame_x + frame_w, frame_y + frame_h), radius=42, fill=(24, 35, 52, 255), outline=(104, 124, 148, 160), width=2)
    draw.rounded_rectangle((frame_x + 18, frame_y + 18, frame_x + frame_w - 18, frame_y + frame_h - 18), radius=28, fill=(10, 14, 24, 255))
    draw.rounded_rectangle((frame_x + 18, frame_y + 18, frame_x + frame_w - 18, frame_y + 18 + chrome_h), radius=28, fill=(30, 41, 59, 255))
    draw.rectangle((frame_x + 18, frame_y + 18 + chrome_h // 2, frame_x + frame_w - 18, frame_y + 18 + chrome_h), fill=(30, 41, 59, 255))
    for i, color in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        cx = frame_x + 58 + i * 32
        cy = frame_y + 47
        draw.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=(*color, 255))
    screen_box = (frame_x + 18, frame_y + 18 + chrome_h, frame_w - 36, frame_h - 36 - chrome_h)
    screen = cover_resize(screenshot, (screen_box[2], screen_box[3]))
    paste_rounded(base, screen, (screen_box[0], screen_box[1]), 22)
    draw.rounded_rectangle((frame_x + 590, frame_y + frame_h + 18, frame_x + 900, frame_y + frame_h + 44), radius=13, fill=(45, 55, 72, 255))
    draw.rounded_rectangle((frame_x + 505, frame_y + frame_h + 42, frame_x + 985, frame_y + frame_h + 70), radius=14, fill=(21, 29, 43, 255))
    draw_text_block(draw, (130, 330), spec.title, spec.subtitle, 550, 92)


def draw_mobile_frame(base: Image.Image, screenshot: Image.Image, spec: PromoSpec) -> None:
    phone_w, phone_h = 760, 1604
    phone_x = (MOBILE_SIZE[0] - phone_w) // 2
    phone_y = 620
    draw_shadow(base, (phone_x - 40, phone_y - 28, phone_x + phone_w + 40, phone_y + phone_h + 54), 92, 46, 155)
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((phone_x, phone_y, phone_x + phone_w, phone_y + phone_h), radius=92, fill=(18, 24, 38, 255), outline=(108, 122, 142, 170), width=4)
    screen_margin = 34
    screen_box = (phone_x + screen_margin, phone_y + screen_margin, phone_w - screen_margin * 2, phone_h - screen_margin * 2)
    screen = cover_resize(screenshot, (screen_box[2], screen_box[3]))
    paste_rounded(base, screen, (screen_box[0], screen_box[1]), 62)
    notch_w, notch_h = 220, 46
    notch_x = phone_x + (phone_w - notch_w) // 2
    draw.rounded_rectangle((notch_x, phone_y + 26, notch_x + notch_w, phone_y + 26 + notch_h), radius=23, fill=(10, 15, 24, 255))
    draw_text_block(draw, (112, 150), spec.title, spec.subtitle, 1220, 88)


def create_desktop_promo(source: Path, output: Path, spec: PromoSpec) -> None:
    screenshot = Image.open(source).convert("RGBA")
    image = create_background(DESKTOP_SIZE, spec.accent)
    draw_desktop_frame(image, screenshot, spec)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output, optimize=True)


def create_mobile_promo(source: Path, output: Path, spec: PromoSpec) -> None:
    screenshot = Image.open(source).convert("RGBA")
    image = create_background(MOBILE_SIZE, spec.accent)
    draw_mobile_frame(image, screenshot, spec)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output, optimize=True)


def discover_desktop_sources(path: Path) -> list[Path]:
    return sorted(path.glob("*.png"))


def discover_mobile_sources(path: Path) -> list[Path]:
    preferred = [
        path / "android_main.png",
        path / "android_grid_file.png",
        path / "android_tab.png",
        path / "android_tag.png",
    ]
    return [item for item in preferred if item.exists()]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create desktop and mobile promotional images from screenshots.")
    parser.add_argument("--desktop-source", type=Path, default=DEFAULT_DESKTOP_SOURCE)
    parser.add_argument("--mobile-source", type=Path, default=DEFAULT_MOBILE_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    desktop_sources = discover_desktop_sources(args.desktop_source)
    mobile_sources = discover_mobile_sources(args.mobile_source)

    if not desktop_sources:
        raise SystemExit(f"No desktop screenshots found in {args.desktop_source}")
    if not mobile_sources:
        raise SystemExit(f"No mobile screenshots found in {args.mobile_source}")

    desktop_output = args.output / "desktop"
    mobile_output = args.output / "mobile"
    desktop_vi_output = args.output / "vi" / "desktop"
    mobile_vi_output = args.output / "vi" / "mobile"

    for index, source in enumerate(desktop_sources):
        spec = DESKTOP_SPECS[index % len(DESKTOP_SPECS)]
        create_desktop_promo(source, desktop_output / f"{index + 1:02d}_{spec.stem}.png", spec)
        vi_spec = DESKTOP_SPECS_VI[index % len(DESKTOP_SPECS_VI)]
        create_desktop_promo(source, desktop_vi_output / f"{index + 1:02d}_{vi_spec.stem}.png", vi_spec)

    for index, source in enumerate(mobile_sources):
        spec = MOBILE_SPECS[index % len(MOBILE_SPECS)]
        create_mobile_promo(source, mobile_output / f"{index + 1:02d}_{spec.stem}.png", spec)
        vi_spec = MOBILE_SPECS_VI[index % len(MOBILE_SPECS_VI)]
        create_mobile_promo(source, mobile_vi_output / f"{index + 1:02d}_{vi_spec.stem}.png", vi_spec)

    print(f"Created {len(desktop_sources)} desktop promo images in {desktop_output}")
    print(f"Created {len(mobile_sources)} mobile promo images in {mobile_output}")
    print(f"Created {len(desktop_sources)} Vietnamese desktop promo images in {desktop_vi_output}")
    print(f"Created {len(mobile_sources)} Vietnamese mobile promo images in {mobile_vi_output}")


if __name__ == "__main__":
    main()
