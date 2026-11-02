"""Optional Cycles setup and matched prototype views. No preference file is saved."""


def configure(
    bpy,
    scene,
    backend="AUTO",
    device_name="",
    cpu=False,
    samples=64,
    width=1800,
    height=1200,
    threads=2,
):
    if min(samples, width, height, threads) < 1:
        raise ValueError("Positive render settings required")
    prefs = bpy.context.preferences.addons["cycles"].preferences
    observed = []
    selected = []
    if cpu:
        scene.cycles.device = "CPU"
    else:
        choices = (
            ("HIP", "OPTIX", "CUDA", "ONEAPI", "METAL")
            if backend == "AUTO"
            else (backend,)
        )
        for kind in choices:
            try:
                prefs.compute_device_type = kind
                prefs.refresh_devices()
            except (TypeError, ValueError):
                if backend != "AUTO":
                    raise
                continue
            candidates = sorted(
                [
                    d
                    for d in prefs.devices
                    if d.type == kind
                    and (
                        not device_name
                        or device_name.casefold() in (d.name + " " + d.id).casefold()
                    )
                ],
                key=lambda d: (d.name, d.id),
            )
            observed.extend(
                dict(name=d.name, id=d.id, type=d.type) for d in prefs.devices
            )
            if candidates:
                if device_name and len(candidates) != 1:
                    raise ValueError("Device selector must identify exactlyone GPU")
                selected = candidates[:1]
                break
        if not selected:
            raise RuntimeError(
                "No matching Cycles GPU; select an installed backend/device or explicitly use --cpu-render. Observed: "
                + str(observed)
            )
        for d in prefs.devices:
            d.use = d in selected
        scene.cycles.device = "GPU"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 8
    scene.cycles.transmission_bounces = 6
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.1
    scene.render.film_transparent = False
    return dict(
        render_device="CPU" if cpu else "GPU",
        selected=[dict(name=d.name, id=d.id, type=d.type) for d in selected],
        observed=observed,
    )


def pose(camera, data, view):
    from mathutils import Vector

    camera.location = view["position"]
    camera.rotation_euler = (
        (Vector(view["target"]) - camera.location).to_track_quat("-Z", "Y").to_euler()
    )
    data.type = view.get("type", "PERSP")
    data.lens = view.get("lens", 26)
    data.ortho_scale = view.get("ortho_scale", 12)


def visibility(scene, camera, plans, view):
    for ob in scene.objects:
        if ob == camera or ob.type == "LIGHT":
            if ob.type == "LIGHT" and ob.get("mc_light_plan"):
                ob.hide_render = bool(
                    view.get("plan") and ob["mc_light_plan"] != view["plan"]
                )
            continue
        hide = False
        if view.get("plan"):
            plan = next(p for p in plans if p["id"] == view["plan"])
            cat = ob.get("mc_category")
            same = ob.get("mc_owner") == plan["owner_id"]
            level = ob.get("mc_level", -1)
            if cat == "site":
                hide = True
            elif ob.type == "MESH":
                hide = not same or (
                    level != plan["level_index"]
                    and cat not in ("stair_tread", "stair_riser", "stair_rail")
                )
                if view["mode"] == "CUTAWAY":
                    hide = (
                        hide
                        or cat
                        in (
                            "roof",
                            "ceiling",
                            "rooflight",
                            "window",
                            "exterior_detail",
                            "exterior_service",
                        )
                        or bool(ob.get("mc_cut_upper"))
                    )
        ob.hide_render = hide
