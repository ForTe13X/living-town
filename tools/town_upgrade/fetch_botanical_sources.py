"""Acquire a small explicit CC0 botanical source set; no model inference.

Powered by Poly Haven (https://polyhaven.com). Live API metadata and supplied
MD5 are checked, then local SHA-256 receipts bind every redistributed file.
No preview renders, website artwork, or model weights are downloaded.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request
from urllib.parse import urlparse

AGENT = "LivingTownAssetRefinement/1.0 (CC0 botanical authoring)"
ASSETS = ("island_tree_02", "pine_tree_01", "tree_small_02", "pine_sapling_medium", "fern_02", "celandine_01", "grass_medium_01")


def digest(path, algorithm="sha256"):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def request(url):
    parsed=urlparse(url)
    if parsed.scheme!='https' or parsed.hostname not in {'api.polyhaven.com','dl.polyhaven.org'}:
        raise ValueError('Unexpected botanical source URL: '+url)
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": AGENT}), timeout=90)


def source_path(root,relative):
    path=(root/relative).resolve()
    if not path.is_relative_to(root.resolve()):raise ValueError('Source path escapes asset folder: '+relative)
    return path


def fetch(entry):
    path, record = entry
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.stat().st_size != record["size"] or digest(path, "md5") != record["md5"]:
        temporary = path.with_suffix(path.suffix + ".partial")
        with request(record["url"]) as remote, temporary.open("wb") as target:
            while block := remote.read(1024 * 1024):
                target.write(block)
        if temporary.stat().st_size != record["size"] or digest(temporary, "md5") != record["md5"]:
            raise ValueError("Source size/MD5 mismatch: " + record["url"])
        temporary.replace(path)
    return {"path": str(path), "source_url": record["url"], "source_md5": record["md5"],
            "bytes": path.stat().st_size, "sha256": digest(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    metadata, jobs = {}, []
    for asset in ASSETS:
        path = output / (asset + "_files.json")
        if path.exists():
            value = json.loads(path.read_text(encoding="utf-8-sig"))
        else:
            with request("https://api.polyhaven.com/files/" + asset) as remote:
                value = json.load(remote)
            path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        metadata[asset] = {"sha256": digest(path), "endpoint": "https://api.polyhaven.com/files/" + asset}
        if asset != "pine_tree_01":
            model = value["gltf"]["2k"]["gltf"]
            jobs.append((output / asset / (asset + "_2k.gltf"), model))
            jobs.extend((source_path(output / asset,name), item) for name, item in model["include"].items())
            # Upstream JPEG glTF diffuse has no alpha channel; explicitly retain
            # the CC0 leaf mask and combine it into RGBA in the Blender pipeline.
            for key in value:
                if "alpha" in key.lower() and "2k" in value[key] and "png" in value[key]["2k"]:
                    jobs.append((output / asset / (key + ".png"), value[key]["2k"]["png"]))
        else:
            # A full pine is 17M triangles. Its CC0 twig/bark maps feed original
            # layered branch geometry; do not acquire the 949MB reference mesh.
            for key in ("twig_diff", "twig_alpha", "twig_nor_gl", "twig_arm", "bark_diff", "bark_nor_gl", "bark_arm"):
                fmt = "png" if key == "twig_alpha" else "jpg"
                jobs.append((output / asset / (key + "." + fmt), value[key]["2k"][fmt]))
    with ThreadPoolExecutor(max_workers=3) as pool:
        receipts = list(pool.map(fetch, jobs))
    # Technical glTF import repair: JPEG cannot contain the separately supplied
    # cutout alpha. Pack those existing channels without generating new art.
    from PIL import Image
    derivatives=[]
    for asset in ASSETS:
        folder=output/asset
        if asset=='pine_tree_01':
            pairs=[(folder/'twig_diff.jpg',folder/'twig_alpha.png',folder/'twig_rgba.png')]
        else:
            doc=json.loads((folder/(asset+'_2k.gltf')).read_text())
            masks=sorted(set(folder.glob('*alpha.png'))|set(folder.glob('Alpha.png')))
            pairs=[]
            for mat in doc['materials']:
                if mat.get('alphaMode','OPAQUE')=='OPAQUE':continue
                tex=mat.get('pbrMetallicRoughness',{}).get('baseColorTexture')
                if tex is None:continue
                img=doc['images'][doc['textures'][tex['index']]['source']]
                base=folder/img['uri']
                match=[m for m in masks if any(word in mat.get('name','').lower() and word in m.name.lower() for word in ('twig','leaves'))]
                mask=match[0] if match else masks[0] if len(masks)==1 else None
                if mask is None:raise ValueError('Ambiguous leaf alpha: '+asset+'/'+mat.get('name',''))
                pairs.append((base,mask,base.with_name(base.stem+'_rgba.png')))
        for base,mask,destination in pairs:
            rgba=Image.open(base).convert('RGBA');alpha=Image.open(mask).convert('L');rgba.putalpha(alpha.resize(rgba.size));rgba.save(destination)
            derivatives.append({'path':destination.relative_to(output).as_posix(),'sha256':digest(destination),'operation':'source diffuse RGB + source alpha channel','source_inputs':{str(p.relative_to(output)):digest(p) for p in (base,mask)}})
            # The original authored card material uses this stable legacy name.
            # Keep it a byte-identical, receipted alias of the fetched RGBA map.
            if asset=='island_tree_02' and destination.name=='island_tree_02_leaves_diff_2k_rgba.png':
                alias=destination.with_name('leaves_rgba.png')
                if alias.exists():
                    if not alias.is_file() or digest(alias)!=digest(destination):
                        raise ValueError('Existing botanical leaf alias differs; preserved: '+str(alias))
                else:
                    alias.write_bytes(destination.read_bytes())
                derivatives.append({'path':alias.relative_to(output).as_posix(),'sha256':digest(alias),
                    'operation':'byte-identical compatibility alias; no image transform',
                    'source_inputs':{destination.relative_to(output).as_posix():digest(destination)}})
    result = {"schema": "living_town.botanical_sources.v1", "credit": "Powered by Poly Haven",
              "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
              "api_terms": "https://github.com/Poly-Haven/Public-API/blob/master/ToS.md",
              "metadata": metadata, "files": [{**r, "path": Path(r["path"]).relative_to(output).as_posix()} for r in receipts],"technical_channel_derivatives":derivatives}
    (output / "source_receipts.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    (output / "NOTICES.txt").write_text("Botanical source assets: Poly Haven, CC0-1.0.\n"+
        "\n".join("https://polyhaven.com/a/"+asset for asset in ASSETS)+"\n"
        "https://polyhaven.com/license\nPowered by Poly Haven (metadata acquisition only).\n"
        "Island tree adapted with authored LODs; pine geometry authored for Living Town using CC0 maps.\n", encoding="utf-8")
    print(json.dumps({"files": len(receipts), "bytes": sum(r["bytes"] for r in receipts), "manifest": str(output / "source_receipts.json")}))


if __name__ == "__main__":
    main()
