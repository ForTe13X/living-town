from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BANNER = "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE · NOT GAMEPLAY"
POSITIONS = [(30, 94), (660, 94), (1290, 94), (345, 558), (975, 558)]


def build(media: Path, output: Path) -> None:
    receipt = json.loads((media / "capture_receipt.json").read_text(encoding="utf-8"))
    if receipt.get("banner") != BANNER:
        raise ValueError("capture banner mismatch")
    captures = receipt.get("captures", [])
    if len(captures) != 5:
        raise ValueError("expected five dispatcher captures")

    canvas = Image.new("RGB", (1920, 1080), "#101219")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.load_default(size=30)
    label_font = ImageFont.load_default(size=19)
    detail_font = ImageFont.load_default(size=16)
    title_box = draw.textbbox((0, 0), BANNER, font=title_font)
    draw.text(
        ((1920 - (title_box[2] - title_box[0])) / 2, 22),
        BANNER,
        fill="#f2e5c5",
        font=title_font,
    )
    draw.rectangle((0, 68, 1919, 71), fill="#d88b57")

    for capture, (x, y) in zip(captures, POSITIONS, strict=True):
        source = Image.open(media / capture["file"]).convert("RGB")
        thumb = source.resize((600, 360), Image.Resampling.LANCZOS)
        draw.rectangle((x, y, x + 620, y + 438), fill="#191b25", outline="#555064", width=2)
        label = f'{capture["ordinal"]:02d}  {capture["action_id"].upper()}'
        detail = f'COMMITTED OFFSET {capture["committed_trace_offset"]:02d} · READ-ONLY VIEW'
        draw.text((x + 12, y + 9), label, fill="#f2e5c5", font=label_font)
        draw.text((x + 610, y + 12), detail, fill="#d88b57", font=detail_font, anchor="ra")
        canvas.paste(thumb, (x + 10, y + 48))
        draw.text(
            (x + 12, y + 414),
            f'fingerprint {capture["frame_fingerprint"][:36]}…',
            fill="#aaa5b5",
            font=detail_font,
        )

    footer = "COMPONENT REVIEW ONLY · DETERMINISTIC HOLDS FROM COMMITTED TRACE FRAMES · NO GAMEPLAY CLAIM"
    footer_box = draw.textbbox((0, 0), footer, font=label_font)
    draw.text(
        ((1920 - (footer_box[2] - footer_box[0])) / 2, 1039),
        footer,
        fill="#aaa5b5",
        font=label_font,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, format="PNG", optimize=False, compress_level=9)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--media", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.media.resolve(), args.output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
