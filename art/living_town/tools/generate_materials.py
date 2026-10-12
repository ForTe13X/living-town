"""Create original, deterministic Living Town PBR textures. No external images.

Each image is periodic in U/V, including matching first/last edge pixels.
Base colour is sRGB; roughness and OpenGL tangent normals are non-colour data.
Heights and texture repeats are specified in metres so normals use real slopes.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


BASE_SIZE = 1024
DATA_SIZE = 512
SEED = 20261011
OUT = Path(__file__).resolve().parents[1] / "textures"
V, U = np.meshgrid(np.linspace(0, 1, BASE_SIZE, dtype=np.float32),
                   np.linspace(0, 1, BASE_SIZE, dtype=np.float32), indexing="ij")
TAU = np.float32(2 * np.pi)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def noise(seed, lo, hi, waves=24):
    """Isotropic band-limited Fourier noise, exactly periodic in both axes."""
    rng = np.random.default_rng(SEED + seed)
    out = np.zeros_like(U)
    for _ in range(waves):
        angle = rng.uniform(0, TAU)
        radius = rng.uniform(lo, hi)
        fx = int(round(np.cos(angle) * radius))
        fy = int(round(np.sin(angle) * radius))
        phase = rng.uniform(0, TAU)
        out += np.sin(TAU * (fx * U + fy * V) + phase)
    return np.clip(out / (np.sqrt(waves / 2) * 3), -1, 1)


def color(hexcode):
    return np.array([int(hexcode[i:i+2], 16) for i in (1, 3, 5)], np.float32)


def tint(base, variation, strength=1):
    return color(base)[None, None, :] + variation[..., None] * strength


def seal(a):
    a = a.copy()
    a[-1] = a[0]
    a[:, -1] = a[:, 0]
    return a


def cellhash(ix, iy, cols, rows, seed=0):
    """Stable cell colour independent of array resolution."""
    ix = np.mod(ix, cols)
    iy = np.mod(iy, rows)
    return np.mod(np.sin(ix * 127.1 + iy * 311.7 + seed * 73.63) * 43758.5453, 1) * 2 - 1


def masonry(cols, rows, gap, stagger=True, waviness=0, seed=0):
    ry = np.floor(V * rows).astype(int) % rows
    y = np.mod(V * rows, 1)
    xfull = U * cols + ((ry % 2) * .5 if stagger else 0)
    cx = np.floor(xfull).astype(int) % cols
    x = np.mod(xfull, 1)
    dx = np.minimum(x, 1-x)
    dy = np.minimum(y, 1-y)
    if waviness:
        dx += np.sin(TAU * y * 2 + cellhash(cx, ry, cols, rows, seed) * 3) * waviness
        dy += np.sin(TAU * x * 2 + cellhash(cx, ry, cols, rows, seed+1) * 3) * waviness
    distance = np.minimum(dx, dy)
    body = smooth(gap, gap+.045, distance)
    variation = cellhash(cx, ry, cols, rows, seed)
    return x, y, body, variation, distance


def slate():
    n = noise(1, 4, 22)
    f = noise(2, 55, 230)
    x, y, body, tile, d = masonry(8, 12, .012, seed=2)
    # Split cleavage lines, a slightly lifted lower edge, dark laid joints.
    cleavage = np.sin(TAU * (V * 96 + .18 * noise(3, 2, 6)))
    face = tint("#4f565b", tile, 13) + (n*9 + f*3 + cleavage*1.2)[..., None]
    face += (smooth(.75, .98, y) * -4)[..., None]
    rgb = color("#333d41") + body[..., None] * (face - color("#333d41"))
    height = body * (.004 + .0007 * tile + .001 * n + .00012 * f + .00022 * cleavage)
    height += body * (1-y) * .001
    rough = .79 + n * .06 + f * .025 - body * .06
    return rgb, rough, height


def lime_plaster():
    broad = noise(10, 1, 5)
    trowel = noise(11, 7, 25)
    grit = noise(12, 60, 260)
    pores = smooth(.35, .68, -grit)
    rgb = tint("#e4decb", broad*10 + trowel*4 + grit*1.3)
    rgb[..., 2] += broad * 2
    rgb -= pores[..., None] * 3.5
    height = broad * .0005 + trowel*.0006 + grit*.00014 - pores*.00015
    return rgb, .91 + trowel*.025 + pores*.035, height


def granite():
    broad = noise(20, 3, 20)
    aggregate = noise(21, 60, 270)
    fine = noise(22, 160, 410)
    x, y, body, stone, d = masonry(5, 8, .022, waviness=.008, seed=8)
    feldspar = smooth(.13, .6, aggregate)
    mica = smooth(.22, .62, -aggregate)
    face = tint("#999b91", stone*10 + broad*9 + fine*5)
    face += feldspar[..., None]*13 - mica[..., None]*23
    face[..., 0] += broad*3
    rgb = color("#77796f") + body[..., None]*(face - color("#77796f"))
    height = body*(.011 + stone*.002 + broad*.0022 + aggregate*.00065 + fine*.00015)
    return rgb, .88 + broad*.045 + mica*.04 - feldspar*.05, height


def cobbles():
    coarse = noise(30, 5, 30)
    grain = noise(31, 80, 280)
    x, y, body, stone, d = masonry(9, 12, .024, waviness=.009, seed=22)
    face = tint("#aaa497", stone*18 + coarse*12 + grain*4)
    face[..., 0] += stone * 4
    face[..., 2] -= stone * 3
    joint = tint("#77776b", grain, 4)
    rgb = joint + body[..., None] * (face-joint)
    crown = np.maximum(0, np.sin(np.pi*x)*np.sin(np.pi*y))
    height = body*(.008 + .006*crown + stone*.0014 + coarse*.0018 + grain*.0002)
    return rgb, .87 + grain*.04 - crown*.09, height


def oak():
    # Ten 20 cm planks; staggered end joints across a 2 m repeat.
    ix = np.floor(U*10).astype(int)%10
    x = np.mod(U*10, 1)
    vy = V*2 + (ix%2)*.5
    iy = np.floor(vy).astype(int)%2
    y = np.mod(vy, 1)
    board = cellhash(ix, iy, 10, 2, 6)
    joint = smooth(.012, .032, np.minimum(x, 1-x))*smooth(.004, .015, np.minimum(y, 1-y))
    bend = noise(40, 1, 7)
    fibre = np.sin(TAU*(U*170 + .45*bend + .06*np.sin(TAU*V*2)))
    growth = np.sin(TAU*(U*36 + .36*bend + .15*np.sin(TAU*V)))
    faint = noise(42, 70, 260)
    face = tint("#a58a65", board*13 + growth*5 + fibre*2 + faint*1.8)
    face[..., 0] += board*2
    face[..., 2] -= growth*1.2
    rgb = color("#65543e") + joint[..., None]*(face-color("#65543e"))
    height = joint*(.0015 + board*.0002 + growth*.00012 + fibre*.00009 + faint*.000035)
    return rgb, .67 + growth*.07 + faint*.025 - joint*.035, height


def sand():
    broad = noise(50, 2, 10)
    grain = noise(51, 95, 390)
    ripple = np.sin(TAU*(V*18 + noise(52, 1, 5)*.3))
    tiny_stone = smooth(.42, .66, grain)
    rgb = tint("#d5c5a2", broad*6 + grain*5 + ripple*1.5)
    rgb -= tiny_stone[..., None]*8
    height = broad*.002 + ripple*.0005 + grain*.00014 + tiny_stone*.0004
    return rgb, .96 + grain*.025, height


def grass():
    patch = noise(60, 2, 10)
    tuft = noise(61, 24, 90)
    fine = noise(62, 100, 240, waves=60)
    # Sparse individual short blades avoid a repeating directional crosshatch.
    rng = np.random.default_rng(SEED+63)
    blade_image = Image.new("L", (BASE_SIZE, BASE_SIZE), 128)
    blade_draw = ImageDraw.Draw(blade_image)
    for _ in range(26000):
        bx, by = rng.uniform(0, BASE_SIZE, 2)
        angle = rng.uniform(-np.pi, np.pi)
        length = rng.uniform(1.8, 5.5)
        ex, ey = bx+np.cos(angle)*length, by+np.sin(angle)*length
        value = int(rng.uniform(70, 194))
        blade_draw.line((bx, by, ex, ey), fill=value, width=1)
        if min(bx, ex)<0:
            blade_draw.line((bx+BASE_SIZE, by, ex+BASE_SIZE, ey), fill=value, width=1)
        elif max(bx, ex)>=BASE_SIZE:
            blade_draw.line((bx-BASE_SIZE, by, ex-BASE_SIZE, ey), fill=value, width=1)
        if min(by, ey)<0:
            blade_draw.line((bx, by+BASE_SIZE, ex, ey+BASE_SIZE), fill=value, width=1)
        elif max(by, ey)>=BASE_SIZE:
            blade_draw.line((bx, by-BASE_SIZE, ex, ey-BASE_SIZE), fill=value, width=1)
    blades = (np.asarray(blade_image, dtype=np.float32)-128)/64
    rgb = tint("#84916b", patch, 7)
    rgb += (tuft*6 + fine*2 + blades*5)[..., None]
    rgb[..., 0] += patch*6
    rgb[..., 1] += tuft*4
    rgb[..., 2] -= tuft*3
    dry = smooth(.15, .6, patch)*smooth(.1, .55, tuft)
    rgb += dry[..., None]*np.array([22, 12, -1])
    height = patch*.002 + tuft*.0025 + fine*.00065 + blades*.0003
    return rgb, .91 + tuft*.045, height


def ceramic_tile():
    fine = noise(70, 50, 200)
    glaze = noise(71, 4, 16)
    x, y, body, tile, d = masonry(4, 4, .013, stagger=False, seed=3)
    # Four 30 cm squares in each direction, with a repeating Brittany blue diamond.
    diamond = 1-smooth(.30, .33, np.abs(x-.5)+np.abs(y-.5))
    inner = 1-smooth(.21, .24, np.abs(x-.5)+np.abs(y-.5))
    ring = diamond-inner
    face = tint("#e0d6bb", tile*4 + fine*1.2 + glaze*2)
    blue = tint("#5c7a88", fine*2 + glaze*3)
    face = face*(1-diamond[..., None])+blue*diamond[..., None]
    face += ring[..., None]*8
    rgb = color("#a69e88") + body[..., None]*(face-color("#a69e88"))
    height = body*(.002 + .00006*glaze + .00002*fine)
    rough = .3 + glaze*.045 + fine*.015 + (1-body)*.5
    return rgb, rough, height


def canvas():
    stain = noise(80, 1, 8)
    fleck = noise(81, 95, 350)
    warp = .5+.5*np.cos(TAU*U*160)
    weft = .5+.5*np.cos(TAU*V*160)
    over = np.sin(TAU*U*80)*np.sin(TAU*V*80)
    weave = (warp+weft)*.5 + over*.1
    rgb = tint("#d2ccb7", stain*6 + fleck*1.8 + (weave-.5)*5)
    height = weave*.00028 + fleck*.000025
    return rgb, .94 + fleck*.025, height


MATERIALS = {
    "slate": (slate, 2.4, "#4f565b", "Weathered charcoal blue-grey split slate; 30 x 20 cm tiles", .007),
    "lime_plaster": (lime_plaster, 2., "#e4decb", "Warm cream lime plaster with trowel marks and pores", .002),
    "granite": (granite, 2., "#999b91", "Grey sage granite masonry; 40 x 25 cm blocks", .018),
    "cobbles": (cobbles, 2., "#aaa497", "Warm grey worn offset cobbles; approximately 22 x 17 cm", .02),
    "oak": (oak, 2., "#a58a65", "Warm weathered oak; 20 cm boards and staggered end joints", .003),
    "sand": (sand, 3., "#d5c5a2", "Pale dune sand with restrained ripples and fine aggregate", .005),
    "grass": (grass, 4., "#84916b", "Sage coastal meadow with tufts and dry straw variation", .008),
    "ceramic_tile": (ceramic_tile, 1.2, "#e0d6bb", "Cream glazed 30 cm tiles with Brittany blue diamonds", .003),
    "canvas": (canvas, 1., "#d2ccb7", "Natural flax canvas with interlaced warp and weft", .0004),
}


def data_map(a):
    a = seal(a).astype(np.float32)
    resized = np.asarray(Image.fromarray(a, "F").resize((DATA_SIZE, DATA_SIZE), Image.Resampling.LANCZOS)).copy()
    return seal(resized)


def normal_map(height, tile_size):
    h = data_map(height)
    unique = h[:-1, :-1]
    pixel_metres = tile_size / (DATA_SIZE-1)
    dx = (np.roll(unique, -1, 1)-np.roll(unique, 1, 1))/(2*pixel_metres)
    dy = (np.roll(unique, -1, 0)-np.roll(unique, 1, 0))/(2*pixel_metres)
    # Image rows increase downwards; tangent-space +V increases upwards.
    n = np.stack((-dx, dy, np.ones_like(dx)), axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    n = np.pad(n, ((0, 1), (0, 1), (0, 0)), mode="wrap")
    return np.round(np.clip(n*.5+.5, 0, 1)*255).astype(np.uint8)


def generate(out):
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"schema_version": 1, "generator": "tools/generate_materials.py", "seed": SEED,
                "license": "Original project-generated procedural textures; no external media used",
                "normal_convention": "OpenGL tangent-space +Y", "basecolor_color_space": "sRGB",
                "roughness_color_space": "Non-Color", "normal_color_space": "Non-Color",
                "edge_policy": "Periodic U/V, opposite edge pixels match exactly", "materials": {}}
    thumbnails = []
    for name, (fn, size, palette, description, relief) in MATERIALS.items():
        rgb, rough, height = fn()
        base = np.round(np.clip(seal(rgb), 0, 255)).astype(np.uint8)
        roughness = np.round(np.clip(data_map(rough), 0, 1)*255).astype(np.uint8)
        normal = normal_map(height, size)
        maps = {"basecolor": base, "roughness": roughness, "normal": normal}
        for kind, array in maps.items():
            assert np.array_equal(array[0], array[-1]), (name, kind, "V seam")
            assert np.array_equal(array[:, 0], array[:, -1]), (name, kind, "U seam")
            Image.fromarray(array).save(out/f"{name}_{kind}.png", optimize=True)
        manifest["materials"][name] = {
            "tile_size_metres": size, "palette_base_srgb": palette, "description": description,
            "basecolor": f"{name}_basecolor.png", "roughness": f"{name}_roughness.png",
            "normal": f"{name}_normal.png", "basecolor_resolution": [BASE_SIZE, BASE_SIZE],
            "data_resolution": [DATA_SIZE, DATA_SIZE], "height_range_metres_approx": relief,
            "roughness_mean": round(float(np.mean(roughness)/255), 4),
            "uv_hint": "Use physical world/object coordinates divided by tile_size_metres; repeat extension",
            "normal_strength": 1.0,
        }
        thumbnails.append((name, size, Image.fromarray(base).resize((320, 320), Image.Resampling.LANCZOS)))
        print(f"{name}: basecolor {BASE_SIZE}, data {DATA_SIZE}; repeat {size:g} m; edge check PASS", flush=True)
    (out/"material_manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    contact = Image.new("RGB", (1080, 1230), "#f1ecdf")
    draw = ImageDraw.Draw(contact)
    try:
        titlefont = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 30)
        font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 21)
    except OSError:
        titlefont = font = ImageFont.load_default()
    draw.text((30, 20), "LIVING TOWN / ORIGINAL MATERIAL LIBRARY", fill="#394649", font=titlefont)
    for i, (name, size, thumb) in enumerate(thumbnails):
        x = 30+(i%3)*350
        y = 80+(i//3)*375
        contact.paste(thumb, (x, y))
        draw.text((x, y+328), f"{name.replace('_', ' ')}  /  {size:g} m", fill="#394649", font=font)
    contact.save(out/"material_contact_sheet.png", optimize=True)
    water_height=.012*np.sin(TAU*(U*5+V*2)+noise(91,1,4)*2)+.004*np.sin(TAU*(U*13-V*7))+.0015*noise(92,20,70)
    Image.fromarray(normal_map(water_height,4)).save(out/'water_normal.png',optimize=True)
    (out/'water_material.json').write_text(json.dumps({'source':'tools/generate_materials.py','license':'Original procedural map','normal':'water_normal.png','normal_convention':'OpenGL tangent-space +Y','tile_size_metres':4,'resolution':[DATA_SIZE,DATA_SIZE]},indent=2),encoding='utf-8')
    print(f"Wrote 27 maps, manifest and contact sheet to {out}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    generate(args.out)
