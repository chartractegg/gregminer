#!/usr/bin/env python3
"""
Generate GregMiner icon files (icon.ico, icon.icns, icon.png).
Run once locally, then commit the outputs.
Requires: pip install Pillow
"""
from PIL import Image, ImageDraw, ImageFont
import os, struct, io

SIZE = 256
OUT  = os.path.dirname(__file__)

def draw_icon(size=SIZE) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d   = ImageDraw.Draw(img)
    # Background circle
    pad = size // 16
    d.ellipse([pad, pad, size - pad, size - pad], fill="#0f6b35")
    # Pickaxe emoji text centred
    try:
        fnt = ImageFont.truetype("/System/Library/Fonts/Apple Color Emoji.ttc", int(size * 0.55))
    except Exception:
        try:
            fnt = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf", int(size * 0.55))
        except Exception:
            fnt = ImageFont.load_default()
    text = "⛏"
    bbox = d.textbbox((0, 0), text, font=fnt)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((size - tw) // 2, (size - th) // 2 - pad), text, font=fnt, embedded_color=True)
    return img

img = draw_icon(SIZE)

# PNG (reference)
img.save(os.path.join(OUT, "icon.png"))
print("Wrote icon.png")

# ICO (Windows) — multiple sizes
ico_sizes = [16, 32, 48, 64, 128, 256]
frames = [draw_icon(s).resize((s, s), Image.LANCZOS) for s in ico_sizes]
frames[0].save(os.path.join(OUT, "icon.ico"), format="ICO",
               sizes=[(s, s) for s in ico_sizes], append_images=frames[1:])
print("Wrote icon.ico")

# ICNS (macOS) — using iconutil-compatible raw bytes
# Simple approach: write a valid ICNS with ic08 (256x256 PNG)
buf = io.BytesIO()
img.save(buf, format="PNG")
png_bytes = buf.getvalue()

icon_data = b"ic08" + struct.pack(">I", 8 + len(png_bytes)) + png_bytes
icns = b"icns" + struct.pack(">I", 8 + len(icon_data)) + icon_data
with open(os.path.join(OUT, "icon.icns"), "wb") as f:
    f.write(icns)
print("Wrote icon.icns")
