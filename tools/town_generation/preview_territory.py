"""Draw an evidence map from actual terrain, street and building records."""
from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

COLORS = ["#ac6b4b", "#66878b", "#b38d4c", "#7e8d5f", "#94758a", "#718db0"]


def _font(size, bold=False):
    from PIL import ImageFont
    names = ["C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else
             "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    for name in names:
        if Path(name).is_file():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def render_map(plan, baseline_root, output):
    from PIL import Image, ImageDraw
    root = Path(baseline_root).resolve()
    spec = importlib.util.spec_from_file_location("map_baseline_reserve", root / "tools/reserve_plan.py")
    terrain = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(terrain)
    master = json.loads((root / "masterplan.json").read_text(encoding="utf-8"))
    landscape = json.loads((root / "landscape_plan.json").read_text(encoding="utf-8"))
    reserve = json.loads((root / "reserve_plan.json").read_text(encoding="utf-8"))
    from territory import make_height_function
    finished_height = make_height_function(plan, root)
    image = Image.new("RGB", (1800, 1300), "#f1eee3")
    draw = ImageDraw.Draw(image)
    draw.text((44, 24), "LIVING TOWN / COMPOUND TERRITORY", font=_font(32, True), fill="#263c3c")
    draw.text((44, 68), "Actual generated parcels, connected streets and terrain / metres / north up",
              font=_font(20), fill="#56655c")
    area = (38, 115, 1285, 1190)
    all_rows = master["buildings"] + plan["buildings"]
    all_points = [p for b in all_rows for p in b["footprint_polygon"]]
    # Concentrate on the inhabited territory, retaining a 45m reserve fringe.
    bounds = (min(p[0] for p in all_points)-45, min(p[1] for p in all_points)-45,
              max(p[0] for p in all_points)+45, max(p[1] for p in all_points)+45)
    x0, y0, x1, y1 = bounds
    scale = min((area[2]-area[0])/(x1-x0), (area[3]-area[1])/(y1-y0))
    ox = area[0] + ((area[2]-area[0])-(x1-x0)*scale)/2
    oy = area[1] + ((area[3]-area[1])-(y1-y0)*scale)/2
    def xy(p):
        return (ox+(p[0]-x0)*scale, oy+(y1-p[1])*scale)
    # Finite relief raster using the same reserve authority as generation.
    step = 6.0
    nx, ny = math.ceil((x1-x0)/step), math.ceil((y1-y0)/step)
    heights = {}
    for iy in range(ny+1):
        for ix in range(nx+1):
            heights[ix, iy] = finished_height(x0+ix*step, y0+iy*step)
    for iy in range(ny):
        for ix in range(nx):
            z = heights[ix, iy]
            t = min(1, max(0, z/45))
            color = tuple(round(a+(b-a)*t) for a,b in zip((222,229,200),(133,160,128)))
            a, b = xy((x0+ix*step,y0+(iy+1)*step)), xy((x0+(ix+1)*step,y0+iy*step))
            draw.rectangle((a[0],a[1],b[0]+1,b[1]+1),fill=color)
            corners = [(x0+(ix+dx)*step,y0+(iy+dy)*step) for dx,dy in ((0,0),(1,0),(1,1),(0,1))]
            zs = [heights[ix+dx,iy+dy] for dx,dy in ((0,0),(1,0),(1,1),(0,1))]
            for level in range(0,81,5):
                hits=[]
                for i,j in ((0,1),(1,2),(2,3),(3,0)):
                    if (zs[i] < level) != (zs[j] < level):
                        f=(level-zs[i])/(zs[j]-zs[i])
                        hits.append(xy([corners[i][k]+f*(corners[j][k]-corners[i][k]) for k in (0,1)]))
                if len(hits)==2:
                    draw.line(hits,fill="#a3b292",width=1)
    coast = [[terrain.CORE.coast_x(y), y] for y in range(math.floor(y0), math.ceil(y1)+5, 5)]
    draw.polygon([xy(p) for p in coast+[[x1,y1+10],[x1,y0-10]]],fill="#b8d8df")
    pond=landscape["pond"]
    cx,cy=pond["center"]
    rx,ry=pond.get("water_radii_m",pond.get("outer_bank_radii_m",[6,4]))
    draw.ellipse((xy((cx-rx,cy+ry)),xy((cx+rx,cy-ry))),fill="#8bb8ba",outline="#758f78",width=2)
    for road in master.get("streets", []):
        points=road.get("points_m", road.get("points", road.get("points_xy", [])))
        if len(points)>1:
            draw.line([xy(p) for p in points], fill="#ede2c9", width=max(2,round(road.get("width",5)*scale)))
    for path in reserve["paths"]:
        points = path["points_m"]
        # Clip before drawing very distant endpoints to keep Pillow work bounded.
        for a,b in zip(points,points[1:]):
            if all(x0-30<p[0]<x1+30 and y0-30<p[1]<y1+30 for p in (a,b)):
                draw.line([xy(a),xy(b)], fill="#a09677", width=2)
    for b in master["buildings"]:
        draw.polygon([xy(p) for p in b["footprint_polygon"]],fill="#92928a",outline="#636d64")
    for b in reserve["buildings"]:
        if x0<b["center"][0]<x1 and y0<b["center"][1]<y1:
            cx,cy=b["center"]
            draw.ellipse((xy((cx-3,cy+3)),xy((cx+3,cy-3))),fill="#8c8d72")
    for road in plan["roads"]:
        points=road.get("points_m",road.get("points_xy",[]))
        width=max(2,round(road["width_m"]*scale))
        draw.line([xy(p) for p in points],fill="#7a8177",width=width+2,joint="curve")
        draw.line([xy(p) for p in points],fill="#f6eedb",width=width,joint="curve")
    district_ids = [d["id"] for d in plan["districts"]]
    colors = {identity:COLORS[i%len(COLORS)] for i,identity in enumerate(district_ids)}
    for b in plan["buildings"]:
        polygon=[xy(p) for p in b["footprint_polygon"]]
        draw.polygon(polygon,fill=colors[b["district"]],outline="#fff8e7",width=1)
        if "entry_threshold_m" in b:
            p=xy(b["entry_threshold_m"])
            draw.ellipse((p[0]-1.5,p[1]-1.5,p[0]+1.5,p[1]+1.5),fill="#f8f5e9")
    draw.rectangle(area,outline="#778776",width=2)
    # All world features are clipped to the map frame, including long trails.
    clean=Image.new("RGB",image.size,"#f1eee3")
    clean.paste(image.crop(area),area[:2])
    image=clean
    draw=ImageDraw.Draw(image)
    draw.text((44,24),"LIVING TOWN / COMPOUND TERRITORY",font=_font(32,True),fill="#263c3c")
    draw.text((44,68),"Actual generated parcels, connected streets and terrain / metres / north up",
              font=_font(20),fill="#56655c")
    # Side panel: genuine counts and the planning contract, not concept art.
    px=1330
    draw.text((px,125),"DISTRICT PROGRAM",font=_font(24,True),fill="#263c3c")
    yy=175
    for i,district in enumerate(plan["districts"]):
        rows=[b for b in plan["buildings"] if b["district"]==district["id"]]
        draw.rectangle((px,yy,px+20,yy+20),fill=colors[district["id"]])
        label=district.get("name",district["id"].replace("_"," ").title())
        draw.text((px+32,yy-2),label,font=_font(19,True),fill="#263c3c")
        draw.text((px+32,yy+29),f"{len(rows)} buildings / {sum(b['floors'] for b in rows)} storeys",
                  font=_font(17),fill="#56655c")
        yy+=85
    yy+=5
    metrics=[f"{len(master['buildings'])} retained town buildings",
             f"{len(plan['buildings'])} generated additions",
             f"{len(reserve['buildings'])} retained reserve facilities",
             f"{len(plan['roads'])} new street / path records",
             "5 m terrain contours",
             "White dots: entrances",
             "Grey: retained urban fabric",
             "Colored footprints: new fabric"]
    for line in metrics:
        draw.text((px,yy),line,font=_font(18),fill="#344b44")
        yy+=34
    draw.text((50,1220),f"Seed {plan['seed']} / topology and site audit: {plan['validation']['status']} / baseline preserved",
              font=_font(20,True),fill="#263c3c")
    draw.text((50,1257),"Plan evidence. Final geometry, materials and engine captures are reviewed separately.",
              font=_font(18),fill="#56655c")
    output=Path(output)
    output.parent.mkdir(parents=True,exist_ok=True)
    image.save(output)
    return output
