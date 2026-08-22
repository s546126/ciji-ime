#!/usr/bin/env python3
"""Build ciji.icns and the AppIcon asset catalog from the master PNG."""

from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MASTER_CANDIDATES = [
    Path("/tmp/ciji-app-icon.png"),
    Path("/opt/cursor/artifacts/assets/ciji-app-icon.png"),
    ROOT / "Ciji" / "Resources" / "ciji-master.png",
]
ASSETS = ROOT / "Ciji" / "Assets.xcassets" / "AppIcon.appiconset"
ICNS_PATH = ROOT / "Ciji" / "Resources" / "ciji.icns"
TEAL = (42, 142, 142, 255)


def load_or_draw() -> Image.Image:
    for path in MASTER_CANDIDATES:
        if path.exists():
            img = Image.open(path).convert("RGBA")
            if img.size != (1024, 1024):
                img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
            return img
    img = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((32, 32, 992, 992), radius=220, fill=TEAL)
    font_path = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"
    font = ImageFont.truetype(font_path, 560)
    text = "词"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((1024 - tw) / 2 - bbox[0], (1024 - th) / 2 - bbox[1] - 20), text, font=font, fill=(255, 255, 255, 255))
    return img


def write_icns(images: dict[bytes, bytes]) -> None:
    chunks = []
    for ostype, data in images.items():
        chunks.append(ostype + struct.pack(">I", 8 + len(data)) + data)
    body = b"".join(chunks)
    ICNS_PATH.parent.mkdir(parents=True, exist_ok=True)
    ICNS_PATH.write_bytes(b"icns" + struct.pack(">I", 8 + len(body)) + body)


def png_bytes(img: Image.Image, size: int) -> bytes:
    from io import BytesIO

    scaled = img.resize((size, size), Image.Resampling.LANCZOS)
    buf = BytesIO()
    scaled.save(buf, format="PNG")
    return buf.getvalue()


def main() -> None:
    master = load_or_draw()
    (ROOT / "Ciji" / "Resources").mkdir(parents=True, exist_ok=True)
    master.save(ROOT / "Ciji" / "Resources" / "ciji-master.png")

    sizes = {
        b"icp4": 16,
        b"icp5": 32,
        b"icp6": 64,
        b"ic07": 128,
        b"ic08": 256,
        b"ic09": 512,
        b"ic10": 1024,
        b"ic11": 32,
        b"ic12": 64,
        b"ic13": 256,
        b"ic14": 512,
    }
    write_icns({k: png_bytes(master, v) for k, v in sizes.items()})

    ASSETS.mkdir(parents=True, exist_ok=True)
    catalog = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, size in catalog:
        master.resize((size, size), Image.Resampling.LANCZOS).save(ASSETS / name)
    (ASSETS / "Contents.json").write_text(
        """{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""",
        encoding="utf-8",
    )
    (ROOT / "Ciji" / "Assets.xcassets" / "Contents.json").write_text(
        """{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n""",
        encoding="utf-8",
    )
    print(f"Wrote {ICNS_PATH} ({ICNS_PATH.stat().st_size} bytes) and {ASSETS}")


if __name__ == "__main__":
    main()
