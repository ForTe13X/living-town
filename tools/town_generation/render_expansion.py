"""Render larger review images from a saved native without changing that file."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    parser.add_argument("--views",nargs="+",default=["overview","street","interior","terrain"])
    parser.add_argument("--width",type=int,default=1400)
    parser.add_argument("--height",type=int,default=960)
    parser.add_argument("--samples",type=int,default=20)
    parser.add_argument("--camera-overrides",type=Path)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    root=args.scene.resolve(strict=True)
    output=args.output.resolve()
    if output.exists():raise FileExistsError(output)
    if not 320<=args.width<=3840 or not 240<=args.height<=2160 or not 1<=args.samples<=128:
        raise ValueError("Render settings outside bounded review profile")
    manifest=json.loads((root/"expansion_manifest.json").read_text(encoding="utf-8"))
    native=root/manifest["native"]["path"]
    before=sha(native)
    if before!=manifest["native"]["sha256"]:raise ValueError("Native binding mismatch")
    overrides=json.loads(args.camera_overrides.read_text(encoding="utf-8")) if args.camera_overrides else {}
    bpy.ops.wm.open_mainfile(filepath=str(native),load_ui=False)
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.device="CPU"
    scene.cycles.samples=args.samples
    scene.cycles.use_denoising=True
    scene.render.threads_mode="FIXED"
    scene.render.threads=6
    scene.render.resolution_x=args.width
    scene.render.resolution_y=args.height
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG"
    output.mkdir(parents=True,exist_ok=False)
    rows=[]
    focus=next(b for b in manifest["buildings"] if b["detail_tier"]=="focus" and b["kind"] in ("cafe","creperie"))
    for view in args.views:
        camera=bpy.data.objects["Expansion_Camera_"+view]
        settings=dict(manifest["cameras"][view])
        settings.update(overrides.get(view,{}))
        camera.location=settings["position"]
        camera.rotation_euler=(Vector(settings["target"])-camera.location).to_track_quat("-Z","Y").to_euler()
        if "ortho" in settings:
            camera.data.type="ORTHO";camera.data.ortho_scale=settings["ortho"]
        else:
            camera.data.type="PERSP";camera.data.lens=settings.get("lens",40)
        scene.camera=camera
        changed=[]
        if view=="interior":
            for role in ("front","roof","upper"):
                col=bpy.data.collections[focus["collections"][role]]
                changed.append((col,col.hide_render));col.hide_render=True
        path=output/("expansion_"+view+".png")
        scene.render.filepath=str(path)
        try:bpy.ops.render.render(write_still=True)
        finally:
            for col,value in changed:col.hide_render=value
        rows.append({"view":view,"path":path.name,"sha256":sha(path),"camera":settings})
    if sha(native)!=before:raise RuntimeError("Read-only render changed native")
    report={"schema":"living_town.expansion_review_renders.v1","status":"PASS",
            "native_sha256":before,"source_unchanged":True,"views":rows,
            "resolution":[args.width,args.height],"samples":args.samples,"device":"CPU","threads":6,
            "scope":"Actual Cycles renders from the generated native. Quality acceptance is a separate visual review."}
    (output/"render_manifest.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__":main()
