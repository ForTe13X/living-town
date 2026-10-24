"""Build an honest, labeled HTML/contact-sheet index of actual native renders.

Expected coverage comes from every source building and authored floor. Each
receipt/image hash and native binding is checked independently of the renderer's
global completion flag. Image presence is never labeled visual acceptance.
Uses standard Python plus Pillow for the contact sheets; no Blender or network.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import html
import json
import math
import os
from pathlib import Path
import textwrap
from urllib.parse import quote


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def key(view):
    return view["building_id"], view["kind"], view.get("level")


def evaluate(buildings_path, receipts_path, native=None):
    from PIL import Image
    manifest, receipt = read(buildings_path), read(receipts_path)
    rows = manifest["buildings"]
    expected = {(r["id"], "exterior", None) for r in rows}
    expected.update((r["id"], "floor", f["level"]) for r in rows for f in r["interior"]["levels"])
    failures, views, seen = [], [], set()
    native_hash = sha(native) if native else receipt.get("native_sha256")
    if native and receipt.get("native_sha256") != native_hash:
        failures.append({"kind": "native_binding_mismatch", "expected": native_hash, "actual": receipt.get("native_sha256")})
    if receipt.get("buildings_sha256") != sha(buildings_path):
        failures.append({"kind": "building_manifest_binding_mismatch", "expected": sha(buildings_path), "actual": receipt.get("buildings_sha256")})
    duplicate_ids = [ident for ident, count in Counter(r["id"] for r in rows).items() if count != 1]
    if duplicate_ids:
        failures.append({"kind": "duplicate_building_ids", "ids": duplicate_ids})
    image_root = Path(receipts_path).resolve().parent
    for source in receipt.get("views", []):
        item, errors = dict(source), []
        identity = key(source)
        if identity in seen:
            errors.append("duplicate view key")
        seen.add(identity)
        if identity not in expected:
            errors.append("unexpected building/floor view")
        if source.get("native_sha256") != native_hash:
            errors.append("view native hash mismatch")
        image_path = (image_root/source["path"]).resolve()
        if not image_path.is_relative_to(image_root):
            errors.append("image path escapes receipt directory")
        elif not image_path.is_file():
            errors.append("missing render file")
        elif sha(image_path) != source.get("sha256"):
            errors.append("render image hash mismatch")
        else:
            with Image.open(image_path) as image:
                item["dimensions_px"] = list(image.size)
                if min(image.size) < 64:
                    errors.append("render resolution too small for inspection")
                rgba = image.convert("RGBA")
                if rgba.getchannel("A").getbbox() is None:
                    errors.append("fully transparent render")
        if source.get("rendered_objects", 0) <= 0:
            errors.append("receipt has no rendered geometry")
        item["absolute_image_path"] = str(image_path)
        item["evidence_status"] = "BOUND" if not errors else "INVALID"
        item["errors"] = errors
        item["visual_acceptance"] = "AWAITING_REVIEW"
        views.append(item)
        if errors:
            failures.append({"kind": "invalid_view", "building_id": identity[0], "view": identity[1], "level": identity[2], "errors": errors})
    missing = sorted(expected-seen, key=lambda x: (x[0], x[1], -1 if x[2] is None else x[2]))
    failures.extend({"kind": "missing_view", "building_id": ident, "view": kind, "level": level} for ident, kind, level in missing)
    complete = not failures and seen == expected
    return {"schema": "living_town.whole_town_visual_catalog_coverage.v1",
            "status": "COMPLETE_EVIDENCE" if complete else "INCOMPLETE_EVIDENCE",
            "visual_acceptance": "AWAITING_REVIEW", "building_count": len(rows),
            "floor_count": sum(len(r["interior"]["levels"]) for r in rows),
            "expected_views": len(expected), "received_views": len(views),
            "bound_views": sum(v["evidence_status"] == "BOUND" for v in views),
            "native_binding": "VERIFIED_FILE_HASH" if native else "RECEIPT_ONLY_NOT_LIVE_VERIFIED",
            "native_sha256": native_hash, "buildings_sha256": sha(buildings_path),
            "render_receipts_sha256": sha(receipts_path), "tool_sha256": sha(__file__),
            "failures": failures, "views": views,
            "limits": ["Image hashes/nonempty alpha establish evidence identity and presence, not acceptable art or furnishings.",
                       "Floor images show actual isolated floor collections. Exterior shell/window design is reviewed separately in exterior images and native geometric aperture tests.",
                       "Real playable behavior, in-situ vegetation, terrain composition and performance require separate game/native walkthrough evidence."]}


def _font(size):
    from PIL import ImageFont
    for path in ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def contact_sheets(report, output, columns=4, rows=5):
    from PIL import Image, ImageDraw, ImageOps
    valid = [v for v in report["views"] if v["evidence_status"] == "BOUND"]
    pages, per_page, cell_w, cell_h = [], columns*rows, 340, 398
    title_font, label_font, small_font = _font(23), _font(14), _font(13)
    sheet_dir = output/"contact_sheets"
    sheet_dir.mkdir(parents=True, exist_ok=True)
    for page_number in range(math.ceil(len(valid)/per_page)):
        page = valid[page_number*per_page:(page_number+1)*per_page]
        canvas = Image.new("RGB", (columns*cell_w+40, rows*cell_h+116), "#f3f1e9")
        draw = ImageDraw.Draw(canvas)
        draw.text((22, 17), f"Living Town / native architectural review {page_number+1:02d}", font=title_font, fill="#23352d")
        draw.text((22, 52), f"{len(report['views'])}/{report['expected_views']} views received • native {report['native_sha256'][:16]}", font=small_font, fill="#40584a")
        draw.text((22, 75), "Actual native renders. Visual acceptance awaits inspection.", font=small_font, fill="#8b5b2b")
        for i, view in enumerate(page):
            x, y = 20+(i % columns)*cell_w, 104+(i//columns)*cell_h
            draw.rounded_rectangle((x, y, x+cell_w-12, y+cell_h-12), radius=9, fill="white")
            with Image.open(view["absolute_image_path"]) as source:
                image = ImageOps.contain(source.convert("RGBA"), (cell_w-28, 310))
                composite = Image.new("RGBA", (cell_w-28, 310), "#e7e9e1")
                composite.alpha_composite(image, ((composite.width-image.width)//2, (composite.height-image.height)//2))
                canvas.paste(composite.convert("RGB"), (x+8, y+8))
            title = view["building_id"]+(" / exterior" if view["level"] is None else f" / L{view['level']:02d}")
            for line_number, line in enumerate(textwrap.wrap(title, width=36)[:3]):
                draw.text((x+10, y+327+line_number*17), line, font=label_font, fill="#26372e")
        path = sheet_dir/f"native_catalog_{page_number+1:02d}.jpg"
        canvas.save(path, quality=91, subsampling=0)
        pages.append({"path": path.relative_to(output).as_posix(), "sha256": sha(path),
                      "views": [{"building_id": v["building_id"], "kind": v["kind"], "level": v["level"]} for v in page]})
    return pages


def _relative_url(path, output):
    try:
        return quote(Path(os.path.relpath(path, output)).as_posix(), safe="/:")
    except ValueError:
        return Path(path).as_uri()


def html_catalog(report, buildings_path, output):
    rows = read(buildings_path)["buildings"]
    by_view = {key(v): v for v in report["views"]}
    esc = lambda value: html.escape(str(value), quote=True)
    parts = ["""<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Living Town native building and floor catalog</title><style>
:root{color-scheme:light;font:15px/1.5 system-ui,sans-serif;color:#26372e;background:#f2f0e7}body{margin:0}header,main{max-width:1500px;margin:auto;padding:28px}h1{font:600 32px/1.2 Georgia,serif;margin:0 0 12px}p{max-width:1000px}.badge{background:#e3eadf;padding:4px 10px;border-radius:16px;margin:0 6px 0 0;display:inline-block;font-size:13px}.pending{background:#f0dfc4}input,select{font:inherit;padding:9px 12px;border:1px solid #a7b3a4;border-radius:7px;background:white}input{min-width:330px}.toolbar{display:flex;gap:10px;flex-wrap:wrap}details{border-top:1px solid #bdc9b7;padding:15px 0}summary{cursor:pointer;font-size:17px;font-weight:650}.meta{color:#65755e;font-size:13px;font-weight:400}.views{display:flex;gap:14px;flex-wrap:wrap;padding-top:15px}figure{margin:0;width:294px;background:white;border-radius:9px;overflow:hidden}figure img{width:294px;height:294px;object-fit:contain;background:#e6e9df}figcaption{padding:10px 12px;font-size:13px}a{color:#285b44}.missing{padding:30px;background:#f3dfcf}.checks{font-size:13px;color:#6c745f}footer{padding:24px 0;font-size:13px;color:#6c745f}code{font-size:12px}body{scroll-behavior:smooth}</style><header>""",
             f"<h1>Living Town · buildings and interiors</h1><p>{report['building_count']} buildings and {report['floor_count']} authored floors. "
             "Each image is a real native render with its source identity checked. Open a building to inspect full images.</p>",
             f"<p><span class='badge'>{report['bound_views']}/{report['expected_views']} bound images</span><span class='badge'>{esc(report['status'])}</span><span class='badge pending'>Visual acceptance awaiting review</span></p>",
             f"<p class='checks'>Native SHA-256 <code>{esc(report['native_sha256'])}</code><br>Exterior and overhead floor cuts isolate the actual model. In-situ landscape and playable evidence remain separate.</p>",
             "<div class='toolbar'><input id='search' placeholder='Find building ID, purpose or type' aria-label='Find building'><select id='group' aria-label='District group'><option value=''>All areas</option><option>urban</option><option>reserve</option><option>expansion</option></select><button id='expand'>Open visible buildings</button></div></header><main>"]
    for ordinal, row in enumerate(rows):
        floors = row["interior"]["levels"]
        room_count = sum(len(f["rooms"]) for f in floors)
        keywords = " ".join([row["id"], row.get("kind", ""), row.get("group", ""), *[r["purpose"] for f in floors for r in f["rooms"]]])
        parts.append(f"<details class='building' data-group='{esc(row.get('group', ''))}' data-search='{esc(keywords.lower())}'{' open' if ordinal < 2 else ''}><summary>{esc(row['id'])} <span class='meta'>· {esc(row.get('kind'))} · {len(floors)} floors · {room_count} zones</span></summary><div class='views'>")
        expected = [(row["id"], "exterior", None)]+[(row["id"], "floor", f["level"]) for f in floors]
        for ident, kind, level in expected:
            view = by_view.get((ident, kind, level))
            label = "Exterior" if level is None else f"Floor L{level:02d}"
            if not view or view["evidence_status"] != "BOUND":
                parts.append(f"<figure><div class='missing'>{esc(label)}<br>Missing or invalid source-bound image.</div></figure>")
                continue
            url = esc(_relative_url(view["absolute_image_path"], output))
            details = ""
            if level is not None:
                floor = next(f for f in floors if f["level"] == level)
                count = sum(len(r.get("assets", [])) for r in floor["rooms"])
                details = f"<br>{len(floor['rooms'])} authored zones · {count} furnishing assemblies"
            parts.append(f"<figure><a href='{url}' target='_blank' rel='noopener'><img src='{url}' loading='lazy' alt='{esc(ident+' '+label)}'></a><figcaption><strong>{esc(label)}</strong>{details}<br>Identity bound; visual acceptance pending.</figcaption></figure>")
        parts.append("</div></details>")
    parts += ["<footer>Room zones include open circulation and do not imply closed rooms. No image-presence check certifies furnishing quality, materials, accessibility or engine behavior.</footer></main>",
              """<script>const boxes=[...document.querySelectorAll('.building')],s=document.querySelector('#search'),g=document.querySelector('#group');function filter(){const q=s.value.toLowerCase();for(const b of boxes)b.hidden=!!((g.value&&b.dataset.group!==g.value)||(q&&!b.dataset.search.includes(q)))}s.addEventListener('input',filter);g.addEventListener('change',filter);document.querySelector('#expand').onclick=()=>{for(const b of boxes)if(!b.hidden)b.open=true};</script></html>"""]
    path = output/"visual_catalog.html"
    path.write_text("\n".join(parts), encoding="utf-8")
    return path


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--buildings", type=Path, required=True)
    p.add_argument("--receipts", type=Path, required=True)
    p.add_argument("--native", type=Path)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--skip-contact-sheets", action="store_true")
    args = p.parse_args(argv)
    args.output.mkdir(parents=True, exist_ok=True)
    report = evaluate(args.buildings, args.receipts, args.native)
    if not args.skip_contact_sheets:
        report["contact_sheets"] = contact_sheets(report, args.output)
    html_catalog(report, args.buildings, args.output)
    (args.output/"visual_catalog_coverage.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "expected": report["expected_views"], "bound": report["bound_views"], "failures": len(report["failures"]), "html": str((args.output/"visual_catalog.html").resolve())}))
    return 0 if report["status"] == "COMPLETE_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
