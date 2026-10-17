#!/usr/bin/env python3
"""Generate promotional images from app screenshots."""

from __future__ import annotations

import argparse
import math
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DESKTOP_SOURCE = ROOT / "screenshots" / "auto" / "desktop"
DEFAULT_MOBILE_SOURCE = ROOT / "screenshots" / "auto" / "android"
LEGACY_MOBILE_SOURCE = ROOT / "screenshots"
DEFAULT_OUTPUT = ROOT / "screenshots" / "promo"

DESKTOP_SIZE = (2400, 1350)
MOBILE_SIZE = (1440, 2560)
TABLET7_SIZE = (1200, 1920)
FEATURE_SIZE = (1024, 500)
STORE_HERO_SIZE = (1920, 1080)
LOGO_PATH = ROOT / "cb_file_manager" / "assets" / "images" / "logo_circle.png"

DESKTOP_SOURCE_NAMES = [
    "002_showcase_file_browser_result.png",
    "004_showcase_gallery_hub_result.png",
    "006_showcase_album_detail_result.png",
    "008_showcase_ai_side_panel_search_result.png",
    "010_showcase_ai_approval_result.png",
    "012_showcase_ai_conversation_result.png",
    "014_showcase_tag_management_result.png",
    "018_showcase_tag_tree_result.png",
    "020_showcase_disk_cleaner_result.png",
]

# Hero frames from the "Mobile showcase" group of
# integration_test/showcase_screenshots_e2e_test.dart, in promo-slot order.
MOBILE_SOURCE_NAMES = [
    "002_mobile_home_result.png",
    "004_mobile_file_grid_result.png",
    "006_mobile_tabs_result.png",
    "008_mobile_tags_result.png",
]

# Hand-captured device screenshots kept as a fallback for checkouts that have
# not run the Android capture yet.
LEGACY_MOBILE_SOURCE_NAMES = [
    "android_main.png",
    "android_grid_file.png",
    "android_tab.png",
    "android_tag.png",
]


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
    PromoSpec("tagged_files", "Navigate tag trees", "Build parent-child tag hierarchies and expand the exact branch you need.", (92, 219, 149)),
    PromoSpec("disk_cleaner", "Clean with confidence", "Scan bulky folders, review junk candidates, and ask CB Agent before deleting.", (255, 149, 0)),
]

MOBILE_SPECS = [
    PromoSpec("mobile_home", "Your file hub on mobile", "Browse and organize files with a touch-first layout.", (54, 166, 255)),
    PromoSpec("mobile_grid", "Large libraries, still fast", "Thumbnails, names, and sizes stay readable on a phone screen.", (250, 169, 64)),
    PromoSpec("mobile_tabs", "Tabs that travel with you", "Switch views without losing your place.", (138, 112, 255)),
    PromoSpec("mobile_tags", "Tags on the go", "Group files into workflows wherever you are.", (92, 219, 149)),
]

TABLET7_SPECS = [
    PromoSpec("tablet7_home", "Your file hub on tablets", "Browse and organize files on a roomy 7-inch layout.", (54, 166, 255)),
    PromoSpec("tablet7_grid", "Scan large libraries faster", "A roomier file list keeps media collections easy to browse.", (250, 169, 64)),
    PromoSpec("tablet7_tabs", "Keep more context open", "Switch tabs and folders without losing your place.", (138, 112, 255)),
    PromoSpec("tablet7_tags", "Organize from the couch", "Use tags to group files into clearer tablet workflows.", (92, 219, 149)),
]

DESKTOP_SPECS_VI = [
    PromoSpec("duyet_tap_tin", "Duyệt mọi thư mục", "Tập tin cục bộ, tab, tag và xem trước nhanh trong một không gian gọn gàng.", (54, 166, 255)),
    PromoSpec("thu_vien_anh", "Thư viện lớn vẫn dễ xem", "Quét album, thư mục media và bộ sưu tập hình ảnh mà không mất ngữ cảnh.", (250, 169, 64)),
    PromoSpec("chi_tiet_album", "Xem album nhanh", "Mở album và tiếp tục duyệt với lưới thumbnail phản hồi tốt.", (75, 204, 143)),
    PromoSpec("tim_kiem_ai", "Tìm kiếm với AI", "Tìm, xem lại và thao tác với tập tin bằng bảng trợ lý tích hợp.", (138, 112, 255)),
    PromoSpec("duyet_thao_tac_ai", "Luôn có quyền kiểm soát", "Xem lại hành động của trợ lý trước khi bất kỳ thay đổi nào diễn ra.", (255, 107, 107)),
    PromoSpec("hoi_dap_ai", "Hỏi về tập tin của bạn", "Trò chuyện với trợ lý hiểu ngữ cảnh ngay bên cạnh workspace.", (102, 217, 232)),
    PromoSpec("quan_ly_tag", "Gắn tag để sắp xếp", "Tạo hệ thống nhẹ cho dự án, tài liệu tham khảo và bộ sưu tập media.", (255, 214, 102)),
    PromoSpec("tap_tin_theo_tag", "Duyệt cây tag", "Tạo phân cấp tag cha con và mở đúng nhánh bạn đang cần.", (92, 219, 149)),
    PromoSpec("don_dep_o_dia", "Dọn dẹp tự tin hơn", "Quét thư mục nặng, xem lại tệp rác và hỏi CB Agent trước khi xóa.", (255, 149, 0)),
]

MOBILE_SPECS_VI = [
    PromoSpec("mobile_trang_chu", "File hub trên điện thoại", "Duyệt và sắp xếp tập tin với giao diện tối ưu cho cảm ứng.", (54, 166, 255)),
    PromoSpec("mobile_luoi_file", "Thư viện lớn vẫn nhanh", "Thumbnail, tên và dung lượng vẫn dễ đọc trên màn hình điện thoại.", (250, 169, 64)),
    PromoSpec("mobile_tab", "Tab đi cùng bạn", "Chuyển qua lại giữa các chế độ xem mà không mất vị trí đang duyệt.", (138, 112, 255)),
    PromoSpec("mobile_tag", "Gắn tag mọi nơi", "Gom tập tin thành các workflow rõ ràng ngay trên điện thoại.", (92, 219, 149)),
]

TABLET7_SPECS_VI = [
    PromoSpec("tablet7_trang_chu", "File hub trên máy tính bảng", "Duyệt và sắp xếp tập tin trên giao diện 7 inch rộng rãi.", (54, 166, 255)),
    PromoSpec("tablet7_luoi_file", "Quét thư viện lớn nhanh hơn", "Danh sách rộng rãi giúp bộ sưu tập media dễ duyệt hơn.", (250, 169, 64)),
    PromoSpec("tablet7_tab", "Giữ nhiều ngữ cảnh đang mở", "Chuyển tab và thư mục mà không mất vị trí đang duyệt.", (138, 112, 255)),
    PromoSpec("tablet7_tag", "Sắp xếp thoải mái hơn", "Dùng tag để gom tập tin thành workflow rõ ràng trên tablet.", (92, 219, 149)),
]


DESKTOP_SPECS_TR = [
    PromoSpec("dosya_tarayici", "Her çalışma alanına göz atın", "Yerel dosyalar, sekmeler, etiketler ve zengin önizlemeler tek bir masaüstü görünümünde.", (54, 166, 255)),
    PromoSpec("galeri_merkezi", "Büyük kitaplıklar için galeri", "Albümleri, medya klasörlerini ve görsel koleksiyonları bağlamı kaybetmeden tarayın.", (250, 169, 64)),
    PromoSpec("album_ayrintisi", "Hızlı medya ayrıntıları", "Albümleri açın ve akıcı küçük resim ızgaralarıyla gezinmeye devam edin.", (75, 204, 143)),
    PromoSpec("yapay_zeka_arama", "Yapay zekâ destekli arama", "Entegre asistan paneliyle dosyaları bulun, inceleyin ve işlem yapın.", (138, 112, 255)),
    PromoSpec("yapay_zeka_onayi", "Kontrol sizde", "Dosyalarınızda bir şey değişmeden önce asistanın işlemlerini gözden geçirin.", (255, 107, 107)),
    PromoSpec("yapay_zeka_sohbet", "Dosyalarınız hakkında sorun", "Çalışma alanınızın yanında dosyaları anlayan bir sohbet sürdürün.", (102, 217, 232)),
    PromoSpec("etiket_yonetimi", "Etiketleyin ve düzenleyin", "Projeler, kaynaklar ve medya koleksiyonları için hafif sistemler kurun.", (255, 214, 102)),
    PromoSpec("etiket_agaci", "Etiket ağaçlarında gezinin", "Üst-alt etiket hiyerarşileri oluşturun ve ihtiyacınız olan dalı açın.", (92, 219, 149)),
    PromoSpec("disk_temizleyici", "Güvenle temizleyin", "Büyük klasörleri tarayın, gereksiz dosyaları inceleyin ve silmeden önce CB Agent'a sorun.", (255, 149, 0)),
]

DESKTOP_SPECS_ZH = [
    PromoSpec("liulan_wenjian", "浏览每一个工作区", "本地文件、标签页、标签和丰富预览，尽在一个专注的桌面视图中。", (54, 166, 255)),
    PromoSpec("tuku", "为大型图库而生", "浏览相册、媒体文件夹和图片收藏，始终不丢失上下文。", (250, 169, 64)),
    PromoSpec("xiangce_xiangqing", "快速查看媒体详情", "打开相册，在流畅的缩略图网格中继续浏览。", (75, 204, 143)),
    PromoSpec("ai_sousuo", "AI 辅助搜索", "通过集成的助手侧边栏查找、查看并处理文件。", (138, 112, 255)),
    PromoSpec("ai_shenhe", "一切尽在掌控", "在文件发生任何更改之前，先审核助手的操作。", (255, 107, 107)),
    PromoSpec("ai_duihua", "询问你的文件", "在当前工作区旁，与理解文件的助手持续对话。", (102, 217, 232)),
    PromoSpec("biaoqian_guanli", "标签与整理", "为项目、参考资料和媒体收藏建立轻量的整理体系。", (255, 214, 102)),
    PromoSpec("biaoqian_shu", "浏览标签树", "建立父子标签层级，展开你需要的那一个分支。", (92, 219, 149)),
    PromoSpec("cipan_qingli", "放心清理", "扫描占用空间的文件夹，检查可清理的文件，删除前先询问 CB Agent。", (255, 149, 0)),
]

# Desktop-only languages that reuse the shared source screenshots. Output goes
# to screenshots/promo/<code>/desktop and feeds the Microsoft Store listings.
EXTRA_DESKTOP_LANGUAGES = {
    "tr": DESKTOP_SPECS_TR,
    "zh": DESKTOP_SPECS_ZH,
}
DISK_CLEANER_STEMS = {"disk_cleaner", "don_dep_o_dia", "disk_temizleyici", "cipan_qingli"}


@dataclass(frozen=True)
class ExtraPromo:
    """Desktop promo with its own source and fixed slot, so existing promo filenames stay stable."""

    slot: int
    # "desktop:<file>" in --desktop-source, or "torrent:<scene>" rendered by
    # cb_file_manager/tool/capture_torrent_screenshots_test.dart (en/vi; other
    # languages fall back to English).
    source: str
    specs: dict[str, PromoSpec]
    # Optional (left, top, right, bottom) crop of the source, e.g. to trim the
    # empty canvas around a rendered dialog.
    crop: tuple[int, int, int, int] | None = None


TORRENT_SOURCE = ROOT / "screenshots" / "features" / "torrents"

EXTRA_DESKTOP_PROMOS = [
    ExtraPromo(11, "torrent:qbittorrent", {
        "en": PromoSpec("torrent_library", "Your torrent library", "Import qBittorrent backups and keep .torrent files and magnet links in one searchable library.", (75, 204, 143)),
        "vi": PromoSpec("thu_vien_torrent", "Thư viện torrent của bạn", "Nhập bản sao lưu qBittorrent, gom file .torrent và magnet vào một thư viện có tìm kiếm.", (75, 204, 143)),
        "tr": PromoSpec("torrent_kitapligi", "Torrent kitaplığınız", "qBittorrent yedeklerini içe aktarın; .torrent dosyalarını ve magnet bağlantılarını aranabilir tek kitaplıkta tutun.", (75, 204, 143)),
        "zh": PromoSpec("zhongzi_ku", "你的种子库", "导入 qBittorrent 备份，将 .torrent 文件和磁力链接集中到一个可搜索的库中。", (75, 204, 143)),
    }, crop=(200, 40, 1240, 860)),
    ExtraPromo(12, "desktop:020_showcase_tag_assignment_result.png", {
        "en": PromoSpec("tag_assignment", "Tag files in seconds", "Pick popular or recent tags, or browse the tag tree, without leaving your files.", (255, 214, 102)),
        "vi": PromoSpec("gan_tag", "Gắn tag trong vài giây", "Chọn tag phổ biến, tag gần đây hoặc duyệt cây tag ngay bên cạnh tập tin.", (255, 214, 102)),
        "tr": PromoSpec("etiketleme", "Saniyeler içinde etiketleyin", "Popüler veya son etiketleri seçin ya da dosyalarınızdan ayrılmadan etiket ağacına göz atın.", (255, 214, 102)),
        "zh": PromoSpec("biaoqian_fenpei", "几秒钟完成标签", "选择常用或最近的标签，或直接浏览标签树，无需离开文件。", (255, 214, 102)),
    }),
]


def extra_promo_source(extra: ExtraPromo, language: str, desktop_source: Path) -> Path:
    kind, name = extra.source.split(":", 1)
    if kind == "desktop":
        source = desktop_source / name
    else:
        localized = TORRENT_SOURCE / language / f"{name}.png"
        source = localized if localized.exists() else TORRENT_SOURCE / "en" / f"{name}.png"
    if not source.exists():
        raise SystemExit(f"Missing promo source: {source}")
    return source
CJK_CLOSING_PUNCTUATION = "，。、；：！？）」』"


def contains_cjk(text: str) -> bool:
    return any("\u3000" <= char <= "\u9fff" or "\uff00" <= char <= "\uffef" for char in text)


def load_font(size: int, bold: bool = False, cjk: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    cjk_candidates = [
        Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"),
        Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc" if bold else "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
        Path("/System/Library/Fonts/PingFang.ttc"),
    ]
    candidates = (cjk_candidates if cjk else []) + [
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
    cjk = contains_cjk(title + subtitle)
    title_font = load_font(title_size, bold=True, cjk=cjk)
    subtitle_font = load_font(round(title_size * 0.34), cjk=cjk)
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
    if contains_cjk(text):
        return wrap_cjk_text(text, font, max_width)
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


def wrap_cjk_text(text: str, font: ImageFont.ImageFont, max_width: int) -> str:
    # CJK text has no spaces: break between characters, keep Latin words such
    # as "CB Agent" whole and never start a line with closing punctuation.
    tokens = re.findall(r"[A-Za-z0-9][A-Za-z0-9.+'\-]*|\s+|.", text)
    lines: list[str] = []
    current = ""
    for token in tokens:
        if token.isspace() and not current:
            continue
        candidate = current + token
        fits = font.getlength(candidate.rstrip()) <= max_width
        if fits or not current.strip() or token in CJK_CLOSING_PUNCTUATION:
            current = candidate
            continue
        lines.append(current.rstrip())
        current = "" if token.isspace() else token
    if current.strip():
        lines.append(current.rstrip())
    return "\n".join(lines)


def draw_desktop_frame(base: Image.Image, screenshot: Image.Image, spec: PromoSpec) -> None:
    frame_x, frame_y = 760, 260
    frame_w, frame_h = 1490, 820
    # Keep the real Windows tab/title bar and its caption buttons visible.
    # A separate decorative title bar duplicates the app's window controls;
    # cover-resizing also crops those controls and the bottom status bar.
    screen = contain_resize(screenshot, (frame_w - 4, frame_h - 4))
    window_w, window_h = screen.width + 4, screen.height + 4
    window_x = frame_x + (frame_w - window_w) // 2
    window_y = frame_y + (frame_h - window_h) // 2
    box = (window_x, window_y, window_x + window_w, window_y + window_h)
    draw_shadow(base, (box[0] - 12, box[1] + 12, box[2] + 12, box[3] + 28), 12, 32, 150)
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle(box, radius=12, fill=(104, 124, 148, 255))
    paste_rounded(base, screen, (window_x + 2, window_y + 2), 10)
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


def draw_tablet7_frame(base: Image.Image, screenshot: Image.Image, spec: PromoSpec) -> None:
    tablet_w, tablet_h = 900, 1200
    tablet_x = (TABLET7_SIZE[0] - tablet_w) // 2
    tablet_y = 560
    draw_shadow(base, (tablet_x - 42, tablet_y - 28, tablet_x + tablet_w + 42, tablet_y + tablet_h + 52), 70, 42, 150)
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((tablet_x, tablet_y, tablet_x + tablet_w, tablet_y + tablet_h), radius=58, fill=(18, 24, 38, 255), outline=(108, 122, 142, 170), width=4)
    screen_margin = 28
    screen_box = (tablet_x + screen_margin, tablet_y + screen_margin, tablet_w - screen_margin * 2, tablet_h - screen_margin * 2)
    screen_background = Image.new("RGBA", (screen_box[2], screen_box[3]), (10, 15, 24, 255))
    screen = contain_resize(screenshot, (screen_box[2], screen_box[3]))
    screen_x = (screen_background.width - screen.width) // 2
    screen_y = (screen_background.height - screen.height) // 2
    screen_background.alpha_composite(screen, (screen_x, screen_y))
    paste_rounded(base, screen_background, (screen_box[0], screen_box[1]), 40)
    camera_r = 7
    camera_x = tablet_x + tablet_w // 2
    camera_y = tablet_y + 14
    draw.ellipse((camera_x - camera_r, camera_y - camera_r, camera_x + camera_r, camera_y + camera_r), fill=(10, 15, 24, 255))
    draw_text_block(draw, (92, 120), spec.title, spec.subtitle, 1010, 76)


def draw_feature_text(draw: ImageDraw.ImageDraw, title: str, subtitle: str, detail: str) -> None:
    title_font = load_font(62, bold=True)
    subtitle_font = load_font(34, bold=True)
    detail_font = load_font(22)
    eyebrow_font = load_font(17, bold=True)
    x, y = 64, 70
    draw.text((x, y), "CB FILE HUB", font=eyebrow_font, fill=(147, 197, 253, 255))
    y += 38
    draw.multiline_text((x, y), wrap_text(title, title_font, 440), font=title_font, fill=(248, 250, 252, 255), spacing=6)
    title_bbox = draw.multiline_textbbox((x, y), wrap_text(title, title_font, 440), font=title_font, spacing=6)
    y = title_bbox[3] + 26
    draw.multiline_text((x, y), wrap_text(subtitle, subtitle_font, 450), font=subtitle_font, fill=(226, 232, 240, 255), spacing=6)
    subtitle_bbox = draw.multiline_textbbox((x, y), wrap_text(subtitle, subtitle_font, 450), font=subtitle_font, spacing=6)
    y = subtitle_bbox[3] + 24
    draw.multiline_text((x, y), wrap_text(detail, detail_font, 410), font=detail_font, fill=(203, 213, 225, 255), spacing=6)


def draw_feature_phone(base: Image.Image, screenshot: Image.Image, xy: tuple[int, int], size: tuple[int, int], tilt: int = 0) -> None:
    phone_w, phone_h = size
    phone = Image.new("RGBA", (phone_w + 80, phone_h + 80), (0, 0, 0, 0))
    offset = 40
    draw = ImageDraw.Draw(phone)
    draw_shadow(phone, (offset - 8, offset - 6, offset + phone_w + 8, offset + phone_h + 12), 42, 20, 120)
    draw.rounded_rectangle((offset, offset, offset + phone_w, offset + phone_h), radius=42, fill=(18, 24, 38, 255), outline=(108, 122, 142, 170), width=2)
    screen_margin = 15
    screen_size = (phone_w - screen_margin * 2, phone_h - screen_margin * 2)
    screen = cover_resize(screenshot, screen_size)
    paste_rounded(phone, screen, (offset + screen_margin, offset + screen_margin), 30)
    notch_w, notch_h = 78, 18
    notch_x = offset + (phone_w - notch_w) // 2
    draw.rounded_rectangle((notch_x, offset + 10, notch_x + notch_w, offset + 10 + notch_h), radius=9, fill=(10, 15, 24, 255))
    if tilt:
        phone = phone.rotate(tilt, resample=Image.Resampling.BICUBIC, expand=True)
    base.alpha_composite(phone, xy)


def create_feature_graphic(sources: list[Path], output: Path, title: str, subtitle: str, detail: str) -> None:
    screenshots = [Image.open(source).convert("RGBA") for source in sources[:3]]
    if not screenshots:
        raise SystemExit("At least one mobile screenshot is required for the feature graphic")

    image = create_background(FEATURE_SIZE, (54, 166, 255))
    overlay = Image.new("RGBA", FEATURE_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rounded_rectangle((570, 42, 984, 458), radius=42, fill=(15, 23, 42, 128), outline=(96, 165, 250, 70), width=2)
    draw.ellipse((760, -120, 1180, 300), fill=(54, 166, 255, 40))
    draw.ellipse((470, 310, 830, 640), fill=(92, 219, 149, 28))
    image = Image.alpha_composite(image, overlay)
    draw = ImageDraw.Draw(image)
    draw_feature_text(draw, title, subtitle, detail)

    first = screenshots[0]
    second = screenshots[1] if len(screenshots) > 1 else first
    third = screenshots[2] if len(screenshots) > 2 else second
    draw_feature_phone(image, second, (690, 100), (186, 392), tilt=7)
    draw_feature_phone(image, third, (790, 88), (176, 372), tilt=-6)
    draw_feature_phone(image, first, (560, 58), (218, 460), tilt=-2)

    output.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output, optimize=True)


def create_desktop_promo(source: Path, output: Path, spec: PromoSpec, crop: tuple[int, int, int, int] | None = None) -> None:
    screenshot = Image.open(source).convert("RGBA")
    if crop:
        screenshot = screenshot.crop(crop)
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


def create_tablet7_promo(source: Path, output: Path, spec: PromoSpec) -> None:
    screenshot = Image.open(source).convert("RGBA")
    image = create_background(TABLET7_SIZE, spec.accent)
    draw_tablet7_frame(image, screenshot, spec)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output, optimize=True)


def create_store_hero(output: Path) -> None:
    """Text-free 16:9 Microsoft Store hero art: no UI, key content above the bottom third."""
    width, height = STORE_HERO_SIZE
    image = create_background(STORE_HERO_SIZE, (54, 166, 255))
    overlay = Image.new("RGBA", STORE_HERO_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    center_x, center_y = width // 2, round(height * 0.40)
    draw.ellipse((center_x - 520, center_y - 420, center_x + 520, center_y + 420), fill=(54, 166, 255, 34))
    draw.ellipse((center_x - 340, center_y - 280, center_x + 340, center_y + 280), fill=(92, 219, 149, 26))
    image = Image.alpha_composite(image, overlay)
    # Abstract file cards around the logo, in the promo accent colors.
    cards = [
        (-560, -170, 210, 150, (54, 166, 255), -8),
        (-470, 150, 180, 128, (250, 169, 64), 6),
        (370, -230, 190, 136, (138, 112, 255), 7),
        (420, 110, 220, 156, (92, 219, 149), -5),
        (-250, -330, 130, 94, (255, 214, 102), 4),
        (190, 250, 140, 100, (255, 107, 107), -7),
    ]
    for dx, dy, card_w, card_h, color, tilt in cards:
        card = Image.new("RGBA", (card_w + 60, card_h + 60), (0, 0, 0, 0))
        card_draw = ImageDraw.Draw(card)
        card_draw.rounded_rectangle((30, 30, 30 + card_w, 30 + card_h), radius=22, fill=(*color, 70), outline=(*color, 150), width=3)
        card_draw.rounded_rectangle((30, 30, 30 + card_w // 2, 30 + card_h // 5), radius=10, fill=(*color, 120))
        card = card.rotate(tilt, resample=Image.Resampling.BICUBIC, expand=True)
        image.alpha_composite(card, (center_x + dx - card.width // 2, center_y + dy - card.height // 2))

    logo = contain_resize(Image.open(LOGO_PATH).convert("RGBA"), (440, 440))
    logo_x, logo_y = center_x - logo.width // 2, center_y - logo.height // 2
    draw_shadow(image, (logo_x + 30, logo_y + 40, logo_x + logo.width - 30, logo_y + logo.height + 10), logo.width // 2, 40, 140)
    image.alpha_composite(logo, (logo_x, logo_y))
    output.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output, optimize=True)


def desktop_promo_filename(index: int, spec: PromoSpec) -> str:
    if spec.stem in DISK_CLEANER_STEMS:
        return f"10_{spec.stem}.png"
    return f"{index + 1:02d}_{spec.stem}.png"


def discover_desktop_sources(path: Path) -> list[Path]:
    sources = [path / name for name in DESKTOP_SOURCE_NAMES]
    missing = [source.name for source in sources if not source.exists()]
    if missing:
        raise SystemExit(f"Missing desktop screenshots in {path}: {', '.join(missing)}")
    return sources


def discover_mobile_sources(path: Path) -> list[Path]:
    candidates = [
        (path, MOBILE_SOURCE_NAMES),
        (path, LEGACY_MOBILE_SOURCE_NAMES),
        (LEGACY_MOBILE_SOURCE, LEGACY_MOBILE_SOURCE_NAMES),
    ]
    for base, names in candidates:
        found = [base / name for name in names if (base / name).exists()]
        if found:
            return found
    return []


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create desktop and mobile promotional images from screenshots.")
    parser.add_argument("--desktop-source", type=Path, default=DEFAULT_DESKTOP_SOURCE)
    parser.add_argument("--mobile-source", type=Path, default=DEFAULT_MOBILE_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--desktop-only", action="store_true", help="Regenerate only desktop promos and the Store hero art.")
    parser.add_argument(
        "--languages",
        default=",".join(["en", "vi", *EXTRA_DESKTOP_LANGUAGES]),
        help="Comma-separated desktop promo languages to (re)generate, e.g. tr,zh.",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    desktop_sources = discover_desktop_sources(args.desktop_source)
    mobile_sources = [] if args.desktop_only else discover_mobile_sources(args.mobile_source)

    if not desktop_sources:
        raise SystemExit(f"No desktop screenshots found in {args.desktop_source}")
    if not args.desktop_only and not mobile_sources:
        raise SystemExit(f"No mobile screenshots found in {args.mobile_source}")

    desktop_output = args.output / "desktop"
    mobile_output = args.output / "mobile"
    tablet7_output = args.output / "tablet7"
    desktop_vi_output = args.output / "vi" / "desktop"
    mobile_vi_output = args.output / "vi" / "mobile"
    tablet7_vi_output = args.output / "vi" / "tablet7"

    languages = {code.strip() for code in args.languages.split(",") if code.strip()}
    unknown = languages - {"en", "vi", *EXTRA_DESKTOP_LANGUAGES}
    if unknown:
        raise SystemExit(f"Unknown promo languages: {', '.join(sorted(unknown))}")
    desktop_targets = []
    if "en" in languages:
        desktop_targets.append(("en", DESKTOP_SPECS, desktop_output))
    if "vi" in languages:
        desktop_targets.append(("vi", DESKTOP_SPECS_VI, desktop_vi_output))
    for code, specs in EXTRA_DESKTOP_LANGUAGES.items():
        if code in languages:
            desktop_targets.append((code, specs, args.output / code / "desktop"))

    for code, specs, output in desktop_targets:
        for index, source in enumerate(desktop_sources):
            spec = specs[index % len(specs)]
            create_desktop_promo(source, output / desktop_promo_filename(index, spec), spec)
        for extra in EXTRA_DESKTOP_PROMOS:
            spec = extra.specs[code]
            source = extra_promo_source(extra, code, args.desktop_source)
            create_desktop_promo(source, output / f"{extra.slot:02d}_{spec.stem}.png", spec, extra.crop)
        print(f"Created {len(desktop_sources) + len(EXTRA_DESKTOP_PROMOS)} desktop promo images in {output}")

    create_store_hero(args.output / "store" / "hero_16x9.png")
    print(f"Created Microsoft Store hero art in {args.output / 'store'}")

    if args.desktop_only:
        return

    for index, source in enumerate(mobile_sources):
        spec = MOBILE_SPECS[index % len(MOBILE_SPECS)]
        create_mobile_promo(source, mobile_output / f"{index + 1:02d}_{spec.stem}.png", spec)
        tablet_spec = TABLET7_SPECS[index % len(TABLET7_SPECS)]
        create_tablet7_promo(source, tablet7_output / f"{index + 1:02d}_{tablet_spec.stem}.png", tablet_spec)
        vi_spec = MOBILE_SPECS_VI[index % len(MOBILE_SPECS_VI)]
        create_mobile_promo(source, mobile_vi_output / f"{index + 1:02d}_{vi_spec.stem}.png", vi_spec)
        tablet_vi_spec = TABLET7_SPECS_VI[index % len(TABLET7_SPECS_VI)]
        create_tablet7_promo(source, tablet7_vi_output / f"{index + 1:02d}_{tablet_vi_spec.stem}.png", tablet_vi_spec)

    create_feature_graphic(
        mobile_sources,
        args.output / "feature_graphic.png",
        "Your file hub anywhere",
        "Browse, play, and organize media anywhere",
        "Tabs, tags, thumbnails, SMB, and FTP in one focused app.",
    )
    create_feature_graphic(
        mobile_sources,
        args.output / "vi" / "feature_graphic.png",
        "File hub trên mọi màn hình",
        "Duyệt, phát và sắp xếp media mọi nơi",
        "Tab, tag, thumbnail, SMB và FTP trong một ứng dụng gọn gàng.",
    )

    print(f"Created {len(mobile_sources)} mobile promo images in {mobile_output}")
    print(f"Created {len(mobile_sources)} 7-inch tablet promo images in {tablet7_output}")
    print(f"Created {len(mobile_sources)} Vietnamese mobile promo images in {mobile_vi_output}")
    print(f"Created {len(mobile_sources)} Vietnamese 7-inch tablet promo images in {tablet7_vi_output}")
    print(f"Created feature graphics in {args.output} and {args.output / 'vi'}")


if __name__ == "__main__":
    main()
