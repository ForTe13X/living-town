"""Customize pinned MIT workflow layouts, offline, without running a model.

The default MultiView variant uses our four Blender RGBA views directly. The
separate research variant retains the Qwen edit subgraph for later evaluation.
Neither variant grants permission to use its third-party models or executes it.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import struct


REPO = Path(__file__).resolve().parents[2]
VENDOR = REPO / "third_party/pixelartistry"
ULTRA_PIN = "64eb9ad10454a51be1c88a7a879b839ced0475c9"
MULTI_PIN = "7cbc1269705d8ba508f6e7a44ffdee44d0ab8f0c"
ULTRA_SOURCE = "PixelArtistry-UltraTex/workflows/UltraTex - 1 Standard 6 views PBR.json"
MULTI_SOURCE = (
    "PixelArtistry-Pixal3D-MultiView/workflows/"
    "PixelArtistry_Qwen2.1_Turnaround_to_Pixal3D_Multiview.json"
)
PINNED_FILES = {
    "PixelArtistry-UltraTex/LICENSE": (ULTRA_PIN, "c5a8cf1fecea4a01a03802831f529b1474c7b72bde15c01356395ccf17ec73d8"),
    ULTRA_SOURCE: (ULTRA_PIN, "bdc592e8804e502ae4e8db584bb3b1f2e8804f43d2ef13aef3b106604303133c"),
    "PixelArtistry-Pixal3D-MultiView/LICENSE": (MULTI_PIN, "95bdac4f86eb398017eb69ee75488ddf54200edb0569f960bf7bffbe54d02c29"),
    MULTI_SOURCE: (MULTI_PIN, "d22cdfccfe1ca72c69bc27ce4664ac2ade1e718b0f18c0d3c81a2a1362a294f6"),
}
VIEW_ORDER = ("front", "left", "back", "right")
CROP_NODES = (338, 341, 342, 345)
CONDITIONING_LINKS = (1389, 1435, 1399, 1436)
FRONT_PROMPT = (
    "One static coastal cafe oak counter with a pale limestone worktop, warm "
    "honey oak framed panels and restrained sage details. Refined stylized "
    "realism, clean readable construction, plausible joinery and subtle grain. "
    "Preserve the supplied counter dimensions, panel count and worktop outline. "
    "Orthographic front view, full object centered, level worktop, entire base "
    "visible, fills 85 percent of a square frame. Neutral even studio lighting, "
    "plain transparent background; no scenery, people, text, logos or baked shadows."
)
SHEET_PROMPT = (
    "Use the counter in <image1> as the exact object reference. Show the same "
    "completely static coastal cafe counter in a single horizontal row of four "
    "equal 1024 by 1024 panels on a 4096 by 1024 sheet. From left to right: front, "
    "left side at exactly 90 degrees, back at exactly 180 degrees, right side at "
    "exactly 270 degrees. Orbit the orthographic camera around the stationary "
    "object; never rotate or redesign the counter. Keep identical dimensions, "
    "worktop shape, joinery, materials and scale; every view has the same base "
    "baseline, framing and neutral even studio lighting. Pale limestone worktop, "
    "warm honey oak panels, restrained sage details, refined stylized realism. "
    "Each panel contains exactly one complete object with clear margins. Plain "
    "transparent background, no scenery, people, text, labels, perspective or baked shadows."
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _nodes(graph: dict) -> dict:
    return {node["id"]: node for node in graph["nodes"]}


def _links(graph: dict):
    for link in graph["links"]:
        if isinstance(link, list):
            yield tuple(link)
        else:
            yield tuple(link[key] for key in (
                "id", "origin_id", "origin_slot", "target_id", "target_slot", "type"
            ))


def _accepts(port: dict, kind: str) -> bool:
    return port["type"] == "*" or kind in port["type"].split(",")


def validate_graph(graph: dict) -> dict:
    """Check both link encodings and real subgraph boundary port references.

    This is layout integrity validation, not a ComfyUI execution test.
    """
    scopes = [graph, *graph.get("definitions", {}).get("subgraphs", [])]
    total_links = total_nodes = 0
    for scope in scopes:
        nodes = _nodes(scope)
        if len(nodes) != len(scope["nodes"]):
            raise ValueError("Duplicate node ID")
        links = list(_links(scope))
        if len({link[0] for link in links}) != len(links):
            raise ValueError("Duplicate link ID")
        indexed = {link[0]: link for link in links}
        in_id = scope.get("inputNode", {}).get("id")
        out_id = scope.get("outputNode", {}).get("id")
        for lid, origin, origin_slot, target, target_slot, kind in links:
            if origin == in_id:
                port = scope["inputs"][origin_slot]
                if lid not in port.get("linkIds", []) or not _accepts(port, kind):
                    raise ValueError(f"Invalid subgraph input boundary: {lid}")
            else:
                try:
                    port = nodes[origin]["outputs"][origin_slot]
                except (KeyError, IndexError) as error:
                    raise ValueError(f"Missing origin port: {lid}") from error
                if lid not in (port.get("links") or []) or not _accepts(port, kind):
                    raise ValueError(f"Invalid origin link: {lid}")
            if target == out_id:
                port = scope["outputs"][target_slot]
                if lid not in port.get("linkIds", []) or not _accepts(port, kind):
                    raise ValueError(f"Invalid subgraph output boundary: {lid}")
            else:
                try:
                    port = nodes[target]["inputs"][target_slot]
                except (KeyError, IndexError) as error:
                    raise ValueError(f"Missing target port: {lid}") from error
                if port.get("link") != lid or not _accepts(port, kind):
                    raise ValueError(f"Invalid target link: {lid}")
        for node in nodes.values():
            for slot, port in enumerate(node.get("inputs", [])):
                if port.get("link") is not None:
                    link = indexed.get(port["link"])
                    if link is None or link[3:5] != (node["id"], slot):
                        raise ValueError("Stale node input link")
            for slot, port in enumerate(node.get("outputs", [])):
                for lid in port.get("links") or []:
                    link = indexed.get(lid)
                    if link is None or link[1:3] != (node["id"], slot):
                        raise ValueError("Stale node output link")
        total_nodes += len(nodes)
        total_links += len(links)
    definitions = {item["id"] for item in scopes[1:]}
    for node in graph["nodes"]:
        if node["id"] in (402, 411) and node["type"] not in definitions:
            raise ValueError("Missing actual nested Qwen definition")
    return {"status": "PASS", "scopes": len(scopes), "nodes": total_nodes,
            "links": total_links, "runtime_execution_tested": False}


def _verify_sources() -> list[dict]:
    provenance = json.loads((VENDOR / "provenance.json").read_text(encoding="utf-8"))
    files = {item["path"]: item for item in provenance["files"]}
    if set(files) != set(PINNED_FILES):
        raise ValueError("Unexpected vendored source inventory")
    for name, (pin, expected_hash) in PINNED_FILES.items():
        item = files[name]
        project, relative = name.split("/", 1)
        expected_url = (f"https://raw.githubusercontent.com/pixelartistry/{project}/{pin}/"
                        + relative.replace(" ", "%20"))
        if (sha256(VENDOR / name) != expected_hash or item["sha256"] != expected_hash
                or item["commit"] != pin or item["license"] != "MIT"
                or item["repository"] != f"https://github.com/pixelartistry/{project}"
                or item["source_url"] != expected_url
                or item["bytes"] != (VENDOR / name).stat().st_size):
            raise ValueError(f"Pinned source changed: {name}")
    return provenance["files"]


def _png_metadata(path: Path, expected_size: tuple[int, int], *, rgba: bool) -> dict:
    with path.open("rb") as stream:
        header = stream.read(33)
    if (len(header) != 33 or header[:8] != b"\x89PNG\r\n\x1a\n"
            or header[8:16] != b"\x00\x00\x00\rIHDR"):
        raise ValueError(f"Not a PNG IHDR: {path}")
    width, height, depth, color, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", header[16:29]
    )
    if ((width, height) != expected_size or depth != 8
            or color not in ((6,) if rgba else (2, 6))
            or (compression, filtering, interlace) != (0, 0, 0)):
        raise ValueError(f"Expected non-interlaced 8-bit {expected_size} "
                         f"{'RGBA' if rgba else 'RGB/RGBA'} PNG: {path}")
    return {"width": width, "height": height, "color_type": color,
            "bit_depth": depth, "validation": "PNG IHDR only; visual review is separate"}


def _set_widget(node: dict, name: str, index: int, value: object) -> None:
    node["widgets_values"][index] = value
    if "widgets_values_named" in node:
        node["widgets_values_named"][name] = copy.deepcopy(value)


def _repoint(graph: dict, link_id: int, origin_id: int, origin_slot: int = 0) -> None:
    nodes = _nodes(graph)
    link = next(link for link in graph["links"] if link[0] == link_id)
    old_links = nodes[link[1]]["outputs"][link[2]]["links"]
    old_links.remove(link_id)
    link[1:3] = [origin_id, origin_slot]
    output = nodes[origin_id]["outputs"][origin_slot]
    if output.get("links") is None:
        output["links"] = []
    output["links"].append(link_id)


def _load_image(node_id: int, input_name: str, title: str, position: list) -> dict:
    return {"id": node_id, "type": "LoadImage", "title": title,
            "pos": position, "size": [320, 300], "flags": {}, "mode": 0,
            "order": 0, "inputs": [],
            "outputs": [{"name": "IMAGE", "type": "IMAGE", "links": []},
                        {"name": "MASK", "type": "MASK", "links": []}],
            "properties": {"cnr_id": "comfy-core", "Node name for S&R": "LoadImage"},
            "widgets_values": [input_name, "image"]}


def _adapt_multi(original: dict) -> dict:
    graph = copy.deepcopy(original)
    nodes = _nodes(graph)
    _set_widget(nodes[402], "prompt", 0, FRONT_PROMPT)
    _set_widget(nodes[402], "switch", 1, False)
    _set_widget(nodes[402], "thinking", 2, False)
    _set_widget(nodes[411], "prompt", 1, SHEET_PROMPT)
    _set_widget(nodes[411], "switch_1", 2, False)
    _set_widget(nodes[411], "switch", 6, True)
    _set_widget(nodes[411], "width", 7, 4096)
    _set_widget(nodes[411], "height", 8, 1024)
    for index, node_id in enumerate(CROP_NODES):
        crop = {"x": index * 1024, "y": 0, "width": 1024, "height": 1024}
        node = nodes[node_id]
        node["title"] = f"Owned sheet: {VIEW_ORDER[index]} ({index * 1024}, 0, 1024, 1024)"
        node["widgets_values"] = [crop, index * 1024, 0, 1024, 1024]
        node["widgets_values_named"] = {"crop_region": copy.deepcopy(crop), **crop}
    for definition in graph["definitions"]["subgraphs"]:
        for node in definition["nodes"]:
            if node["type"] == "TextEncodeQwenImage21":
                _set_widget(node, "prompt", 0,
                            FRONT_PROMPT if node["id"] == 452 else SHEET_PROMPT)
            if node["id"] in (474, 584):
                _set_widget(node, "switch", 0, False)
            if node["type"] == "TextGenerate":
                node["mode"] = 2
                _set_widget(node, "prompt", 0, FRONT_PROMPT if node["id"] == 471 else SHEET_PROMPT)
            if node["id"] in (473, 577, 472, 580):
                node["mode"] = 2
            if node["type"] == "PrimitiveStringMultiline":
                _set_widget(node, "value", 0,
                            "Optional prompt enhancer disabled. Preserve the static counter "
                            "and exact orthographic 90 degree view instructions verbatim.")
    notes = {
        501: "# Living Town offline adaptation\nDefault: four owned Blender RGBA views directly into Pixal3D conditioning. This file is not an execution permit. No model has run.",
        502: "# Separate licenses\nMIT covers this workflow source. Qwen-Image 2.1 research weights are blocked. Pixal3D weights being MIT does not clear the separate DINOv3 license or backend gate. No weights or node dependencies were downloaded.",
        503: "# Static coastal cafe counter\nWarm oak panels, pale limestone worktop, restrained sage details. Match owned geometry and dimensions. Neutral studio reference; no characters, logos or baked lighting.",
        504: "# Exact view order\nfront / left / back / right at 0 / 90 / 180 / 270 degrees. Orbit the camera around a stationary object. Equal framing and baseline. Optional prompt enhancers are disabled in exposed and nested nodes.",
        505: "# Fixed sheet contract\n4096 x 1024 only. Four non-overlapping 1024-square panels: x = 0, 1024, 2048, 3072; y = 0. Reject a differently sized generated sheet rather than borrowing example crop values.",
        506: "# Review gate\nGeneration is untested and disabled by this offline adapter's policy. A proposed mesh must pass silhouette, dimensions, UV, PBR and in-engine review before any town substitution. Existing town assets are not replaced.",
    }
    for node_id, note in notes.items():
        _set_widget(nodes[node_id], "text", 0, note)
    for node in graph["nodes"]:
        if node["type"] in ("SaveImageAdvanced", "Save3DAdvanced"):
            current = node["widgets_values"][0]
            node["widgets_values"][0] = "LivingTown/refinement/" + current.split("/")[-1]
            if "widgets_values_named" in node:
                named = node["widgets_values_named"]
                for key in ("filename_prefix", "filename", "output_path"):
                    if key in named:
                        named[key] = node["widgets_values"][0]
    graph["extra"]["living_town_refinement"] = {
        "execution_permitted": False, "adapter_runs_inference": False,
        "view_order": list(VIEW_ORDER), "sheet_size": [4096, 1024],
        "license_notice": "MIT workflow layout; dependencies and weights require separate review."
    }
    return graph


def _owned_multi(original: dict, staged: dict) -> dict:
    graph = _adapt_multi(original)
    # All original image generation, background removal and recentering stages
    # stay visible for comparison but cannot be dependencies of owned views.
    disabled = {192, 193, 312, 338, 340, 341, 342, 343, 344, 345, 346,
                348, 349, 350, 351, 352, 353, 401, 402, 403, 411, 412}
    for node in graph["nodes"]:
        if node["id"] in disabled:
            node["mode"] = 2
    for index, view in enumerate(VIEW_ORDER):
        node_id = 703 + index
        graph["nodes"].append(_load_image(
            node_id, staged[view], f"Owned Blender RGBA: {view}", [-2300, 350 + index * 360]
        ))
        _repoint(graph, CONDITIONING_LINKS[index], node_id)
    graph["last_node_id"] = 706
    graph["extra"]["living_town_refinement"]["variant"] = "OWNED_VIEW_INPUT"
    return graph


def _research_multi(original: dict, staged_reference: str) -> dict:
    graph = _adapt_multi(original)
    graph["nodes"].append(_load_image(
        703, staged_reference, "Owned front reference for optional Qwen research edit", [-6800, 1500]
    ))
    _repoint(graph, 1504, 703)
    # T2I is optional: edit from the supplied real counter instead of silently
    # inventing geometry from the upstream character example.
    for node in graph["nodes"]:
        if node["id"] in (401, 402, 403):
            node["mode"] = 2
    graph["last_node_id"] = 703
    graph["extra"]["living_town_refinement"]["variant"] = "QWEN_RESEARCH_BLOCKED"
    return graph


def _ultra(original: dict, staged_mesh: str, staged_reference: str, atlas_validated: bool) -> dict:
    graph = copy.deepcopy(original)
    nodes = _nodes(graph)
    nodes[1]["widgets_values"][0] = staged_reference
    nodes[2]["widgets_values"][0] = staged_mesh
    nodes[14]["widgets_values"][3] = "keep_existing" if atlas_validated else "comfy_gpu"
    # LoadImage MASK is inverse alpha; foreground removal weights are unnecessary
    # for the explicit owned RGBA input.
    nodes[14]["widgets_values"][5] = "background (LoadImage)"
    _repoint(graph, 8, 1, 1)
    nodes[3]["mode"] = nodes[4]["mode"] = 2
    nodes[23]["widgets_values"][1] = "LivingTown/refinement/ultratex_counter"
    for node in graph["nodes"]:
        if node["type"] == "MarkdownNote":
            node["widgets_values"] = [
                "# Living Town UltraTex layout adaptation\nPinned MIT source; no inference performed. "
                "The default FLUX.2 Klein base 9B model is blocked for the project's "
                "license-free asset route. This graph is a review artifact, not a runnable "
                "approval. An incompatible 4B substitution is not claimed.\n"
                "Owned RGBA uses inverse LoadImage alpha as the background mask. "
                "The text conditioning stays empty because this pipeline is image-driven.\n"
                f"UV mode: {'keep_existing (caller supplied a validated 0..1 atlas contract)' if atlas_validated else 'comfy_gpu (atlas contract not validated; preserve-existing mode forbidden)'}. "
                "Overlapping metric UVs do not qualify as a unique atlas."
            ]
    graph.setdefault("extra", {})["living_town_refinement"] = {
        "variant": "ULTRATEX_9B_BLOCKED", "execution_permitted": False,
        "adapter_runs_inference": False, "atlas_validated_by_caller": atlas_validated,
        "license_notice": "MIT workflow source only; FLUX.2 Klein base 9B noncommercial gate remains blocked."
    }
    return graph


def build_variants(output_dir, mesh_path, reference_path, sheet_path, *, atlas_validated=False) -> dict:
    """Write three review-only layouts and a source-bound manifest to a new folder.

    Four owned PNGs named front/left/back/right.png must accompany the sheet.
    ``atlas_validated`` is a caller-supplied acceptance result, not a UV audit
    performed by this adapter. It must come from the separate atlas contract.
    """
    if not isinstance(atlas_validated, bool):
        raise ValueError("atlas_validated must be a boolean acceptance result")
    output = Path(output_dir).resolve()
    if output.exists():
        raise FileExistsError(f"Refuse to overwrite an existing output directory: {output}")
    sources = _verify_sources()
    mesh, reference, sheet = (Path(value).resolve(strict=True) for value in (
        mesh_path, reference_path, sheet_path
    ))
    if not mesh.is_file() or mesh.suffix.lower() not in (".glb", ".obj", ".ply"):
        raise ValueError("Expected an existing GLB, OBJ or PLY mesh")
    reference_meta = _png_metadata(reference, (1024, 1024), rgba=True)
    sheet_meta = _png_metadata(sheet, (4096, 1024), rgba=True)
    views = {name: sheet.parent / f"{name}.png" for name in VIEW_ORDER}
    for path in views.values():
        if not path.is_file():
            raise FileNotFoundError(f"Required owned Blender RGBA view: {path}")
        _png_metadata(path, (1024, 1024), rgba=True)
    bindings = {"mesh": mesh, "reference": reference, "sheet": sheet,
                **{f"view_{name}": path for name, path in views.items()}}
    for path in bindings.values():
        if output == path or output in path.parents:
            raise ValueError("Input paths cannot be inside the new output directory")
    # Distinct roles use deterministic staging names, so same-named files from
    # different source directories cannot alias each other in ComfyUI/input.
    staged_mesh = f"living_town_refinement/counter{mesh.suffix.lower()}"
    staged_reference = "living_town_refinement/reference.png"
    staged_views = {name: f"living_town_refinement/{name}.png" for name in VIEW_ORDER}
    ultra_original = json.loads((VENDOR / ULTRA_SOURCE).read_text(encoding="utf-8"))
    multi_original = json.loads((VENDOR / MULTI_SOURCE).read_text(encoding="utf-8"))
    for graph in (ultra_original, multi_original):
        validate_graph(graph)
    graphs = {
        "multiview_owned_views.json": _owned_multi(multi_original, staged_views),
        "multiview_qwen_research_BLOCKED.json": _research_multi(multi_original, staged_reference),
        "ultratex_standard_9b_BLOCKED.json": _ultra(
            ultra_original, staged_mesh, staged_reference, atlas_validated
        ),
    }
    for name, graph in graphs.items():
        project = "PixelArtistry-UltraTex" if name.startswith("ultratex") else "PixelArtistry-Pixal3D-MultiView"
        # Keep the copyright and full MIT notice inside each derivative too, so
        # the attribution survives copying a layout separately from this repo.
        graph["extra"]["living_town_refinement"]["workflow_source_license_notice"] = (
            VENDOR / project / "LICENSE"
        ).read_text(encoding="utf-8")
    payloads = {name: _json_bytes(graph) for name, graph in graphs.items()}
    manifest = {
        "schema": "living-town.asset-refinement-workflows.v1",
        "status": "OFFLINE_LAYOUTS_READY_INFERENCE_NOT_RUN",
        "default_workflow": "multiview_owned_views.json",
        "execution": {"permitted": False, "performed": False,
                      "installs": False, "downloads_models": False,
                      "queues_comfyui": False, "runtime_tested": False,
                      "reason": "Static source customization only; model/dependency license and backend gates remain."},
        "source_files": sources,
        "inputs": {role: {"path": Path(os.path.relpath(path, output)).as_posix(),
                          "sha256": sha256(path), "bytes": path.stat().st_size}
                   for role, path in bindings.items()},
        "image_contract": {"reference": reference_meta, "sheet": sheet_meta,
                           "owned_views": list(VIEW_ORDER), "panel_size": [1024, 1024],
                           "panel_rectangles": [
                               {"view": name, "x": index * 1024, "y": 0, "width": 1024, "height": 1024}
                               for index, name in enumerate(VIEW_ORDER)
                           ],
                           "views_match_sheet_pixels_verified": False,
                           "note": "Source-bound dimensions only; owned Blender render/camera and visual checks establish correspondence."},
        "manual_input_staging": {
            "performed": False, "destination_root": "ComfyUI/input",
            "files": [{"input_role": "mesh", "destination": staged_mesh},
                      {"input_role": "reference", "destination": staged_reference},
                      *[{"input_role": f"view_{name}", "destination": staged_views[name]}
                        for name in VIEW_ORDER]],
            "note": "Future approved runtime must explicitly stage these files. No host files are copied by this adapter."
        },
        "uv": {"atlas_validated_by_caller": atlas_validated,
               "ultratex_mode": "keep_existing" if atlas_validated else "comfy_gpu",
               "audit_performed_by_adapter": False,
               "required_contract": "Unique non-overlapping 0..1 UV atlas on the exact input mesh; metric/repeating UVs are ineligible."},
        "parameters": {
            "ultratex": {"views": 6, "sampler_resolution": 1024, "sampler_steps": 25,
                         "paired_albedo_mr_seed": 12345, "bake_texture_size": 2048,
                         "text_prompt": "", "model_variant": "9B-specific; blocked"},
            "multiview": {"view_order": list(VIEW_ORDER), "conditioning_fov": 20,
                          "research_edit_resolution": [4096, 1024], "research_edit_steps": 25,
                          "research_prompt_enhancement": False,
                          "owned_view_alpha": "Files retain RGBA; ComfyUI LoadImage exposes RGB IMAGE and inverse-alpha MASK separately. Default conditioning receives IMAGE; no inference validation is claimed."}
        },
        "gates": {
            "workflow_source": {"status": "MIT", "scope": "Only the four vendored source files; preserve both license notices."},
            "ultratex_9b": {"status": "BLOCKED_NONCOMMERCIAL", "model": "FLUX.2 Klein base 9B",
                            "note": "Separate base-weight terms; matching UltraTex LoRA is 9B-specific. No 4B compatibility claim."},
            "qwen_research": {"status": "BLOCKED_RESEARCH_LICENSE", "model": "Qwen-Image 2.1"},
            "owned_multiview": {"status": "MANUAL_REVIEW_REQUIRED",
                                "pixal3d_weight_license": "MIT; does not clear the whole pipeline",
                                "pending": ["DINOv3 weight license eligibility", "Every required node and dependency license", "AMD 8060S backend compatibility and resource test", "Generated mesh and PBR quality review"],
                                "avoided": ["Qwen generation weights", "Prompt enhancer weights", "Background removal weights"],
                                "note": "No inference or performance claim; owned RGBA views go directly to the original conditioning node."}
        },
        "workflows": {name: {"sha256": hashlib.sha256(payloads[name]).hexdigest(),
                             "bytes": len(payloads[name]),
                             "integrity": validate_graph(graph)}
                      for name, graph in graphs.items()},
    }
    # Validate every graph and input before creating any output. Exclusive file
    # creation prevents a repeated invocation from silently replacing evidence.
    output.mkdir(parents=True, exist_ok=False)
    for name, data in {**payloads, "workflow_manifest.json": _json_bytes(manifest)}.items():
        with (output / name).open("xb") as stream:
            stream.write(data)
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mesh", required=True, type=Path)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--sheet", required=True, type=Path)
    parser.add_argument("--atlas-validated", action="store_true",
                        help="Only after a separate audit accepts the exact input's unique 0..1 atlas")
    args = parser.parse_args(argv)
    record = build_variants(args.output, args.mesh, args.reference, args.sheet,
                            atlas_validated=args.atlas_validated)
    print(json.dumps({"status": record["status"], "output": str(args.output),
                      "execution_performed": False}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
