#!/usr/bin/env python3
"""Generate Record++ app icon and .icns file."""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os
import subprocess
import shutil
import tempfile

SIZE = 1024
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PNG_PATH = os.path.join(SCRIPT_DIR, "AppIcon.png")
ICNS_PATH = os.path.join(SCRIPT_DIR, "AppIcon.icns")
ASSETS_ICON = os.path.join(SCRIPT_DIR, "Assets.xcassets", "AppIcon.appiconset", "icon_1024x1024.png")


def draw_rounded_rect(draw, xy, r, fill):
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=r, fill=fill)


def create_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    bg_r = int(SIZE * 0.225)
    bg_margin = int(SIZE * 0.04)
    draw_rounded_rect(draw, (bg_margin, bg_margin, SIZE - bg_margin, SIZE - bg_margin), bg_r, (30, 30, 35, 255))

    for i in range(3):
        y_off = int(SIZE * 0.22) + i * int(SIZE * 0.28)
        overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        odraw = ImageDraw.Draw(overlay)
        color = (60, 60, 68, 40) if i % 2 == 0 else (45, 45, 52, 30)
        odraw.rectangle((bg_margin, y_off, SIZE - bg_margin, y_off + int(SIZE * 0.12)), fill=color)
        img = Image.alpha_composite(img, overlay)
        draw = ImageDraw.Draw(img)

    win_w = int(SIZE * 0.42)
    win_h = int(SIZE * 0.32)
    win_x = (SIZE - win_w) // 2
    win_y = int(SIZE * 0.28)
    win_r = int(SIZE * 0.04)

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(
        (win_x + 6, win_y + 6, win_x + win_w + 6, win_y + win_h + 6),
        radius=win_r, fill=(0, 0, 0, 60)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=8))
    img = Image.alpha_composite(img, shadow)
    draw = ImageDraw.Draw(img)

    draw_rounded_rect(draw, (win_x, win_y, win_x + win_w, win_y + win_h), win_r, (55, 55, 62, 255))

    title_h = int(SIZE * 0.07)
    draw_rounded_rect(draw, (win_x, win_y, win_x + win_w, win_y + win_r), win_r, (42, 42, 48, 255))
    draw.rectangle((win_x, win_y + win_r // 2, win_x + win_w, win_y + title_h), fill=(42, 42, 48, 255))

    dot_r = int(SIZE * 0.014)
    dot_y = win_y + title_h // 2
    colors = [(255, 95, 87, 255), (255, 189, 46, 255), (39, 201, 63, 255)]
    for j, c in enumerate(colors):
        cx = win_x + int(SIZE * 0.045) + j * int(SIZE * 0.035)
        draw.ellipse((cx - dot_r, dot_y - dot_r, cx + dot_r, dot_y + dot_r), fill=c)

    content_t = win_y + title_h + int(SIZE * 0.01)
    content_b = win_y + win_h - int(SIZE * 0.01)
    grid_color = (70, 70, 78, 40)
    for j in range(4):
        ly = content_t + (content_b - content_t) * (j + 1) // 5
        draw.line((win_x + int(SIZE * 0.04), ly, win_x + win_w - int(SIZE * 0.04), ly), fill=grid_color, width=2)

    rec_r = int(SIZE * 0.085)
    rec_cx = int(SIZE * 0.65)
    rec_cy = int(SIZE * 0.62)

    for k in range(3):
        gr = rec_r + 8 + k * 4
        glow_alpha = int(50 - k * 15)
        glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow)
        gdraw.ellipse((rec_cx - gr, rec_cy - gr, rec_cx + gr, rec_cy + gr), fill=(255, 69, 58, glow_alpha))
        glow = glow.filter(ImageFilter.GaussianBlur(radius=3 + k))
        img = Image.alpha_composite(img, glow)
        draw = ImageDraw.Draw(img)

    ring_w = int(SIZE * 0.016)
    draw.ellipse(
        (rec_cx - rec_r - ring_w, rec_cy - rec_r - ring_w, rec_cx + rec_r + ring_w, rec_cy + rec_r + ring_w),
        outline=(255, 69, 58, 180), width=ring_w
    )

    draw.ellipse((rec_cx - rec_r, rec_cy - rec_r, rec_cx + rec_r, rec_cy + rec_r), fill=(255, 69, 58, 255))

    try:
        font_size = int(SIZE * 0.08)
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except Exception:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/SF-Pro-Display-Heavy.otf", font_size)
        except Exception:
            font = ImageFont.load_default()

    if font:
        text = "++"
        bbox = draw.textbbox((0, 0), text, font=font)
        tx = int(SIZE * 0.72)
        ty = int(SIZE * 0.78)
        draw.text((tx + 2, ty + 2), text, font=font, fill=(180, 180, 190, 180))
        draw.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))

    img.save(PNG_PATH, "PNG")
    print(f"PNG icon saved to {PNG_PATH}")

    shutil.copy2(PNG_PATH, ASSETS_ICON)
    print(f"Assets icon saved to {ASSETS_ICON}")

    make_icns()


def make_icns():
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        iconset = os.path.join(tmpdir, "icon.iconset")
        os.makedirs(iconset)

        for name, size in sizes.items():
            dst = os.path.join(iconset, name)
            subprocess.run(["sips", "-z", str(size), str(size), PNG_PATH, "--out", dst],
                           capture_output=True, check=True)

        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", ICNS_PATH], check=True)

    print(f"ICNS icon saved to {ICNS_PATH}")


if __name__ == "__main__":
    create_icon()