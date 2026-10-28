"""Pure character-camera math for a caller-verified native pose and editor view.

Coordinates and transforms use centimeters and Z-up. FOV is horizontal. Callers
must independently verify the editor's axis policy, unpiloted non-stereo view,
and lack of view modifiers. The fixed 100 cm depth margin is a conservative
model policy, not a readback of the native near plane or projection matrix.
No Blender, Unreal, filesystem, package or graphics dependency is used.
"""
import hashlib, json, math

def need(v, m):
    if not v:
        raise ValueError(m)

def vec(v, n=3):
    need(isinstance(v, (list, tuple)) and len(v) == n and all((type(x) in (int, float) and math.isfinite(x) for x in v)), 'Finite numeric vector required')
    return [float(x) for x in v]

def dot(a, b):
    # Retain the executed UE Python 3.11 accumulation order on newer hosts.
    # Python 3.12 changed built-in float sum; projection receipts use 3.11.
    total = 0.0
    for x, y in zip(a, b):
        total += x * y
    return total

def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

def unit(v):
    v = vec(v)
    length = math.sqrt(dot(v, v))
    need(length > 1e-12, 'Nonzero direction')
    return [x / length for x in v]

def world_vertices(pose, expected_vertex_count=10707):
    """Transform every declared native render vertex; never infer or trim the expected count."""
    need(type(expected_vertex_count) is int and expected_vertex_count > 0, 'Positive explicit expected vertex count required')
    need(isinstance(pose, dict) and pose.get('status') == 'READ_ACTUAL_CPU_SKINNED_POSE_EXPLICIT_EVALUATION', 'Actual native posed geometry required')
    need(isinstance(pose.get('component_space_positions_cm'), (list, tuple)), 'Native render-vertex sequence required')
    positions = pose['component_space_positions_cm']
    need(len(positions) == expected_vertex_count, 'Every native render vertex required')
    t = pose.get('component_to_world')
    need(isinstance(t, dict), 'Native component_to_world transform required')
    translation = vec(t.get('translation'))
    scale = vec(t.get('scale'))
    q = vec(t.get('rotation_xyzw'), 4)
    need(all((s > 0 for s in scale)) and abs(dot(q, q) - 1.0) < 1e-05, 'Finite positive component scale/unit rotation required')
    xyz = q[:3]
    w = q[3]
    out = []
    for p in positions:
        v = [x * s for x, s in zip(vec(p), scale)]
        uv = cross(xyz, v)
        uuv = cross(xyz, uv)
        out.append([v[k] + 2.0 * (w * uv[k] + uuv[k]) + translation[k] for k in range(3)])
    need(all((math.isfinite(x) for p in out for x in p)), 'Finite actual world vertices')
    return out

def basis(forward):
    f = unit(forward)
    r = unit(cross([0.0, 0.0, 1.0], f))
    up = cross(f, r)
    return (f, r, up)

def _projection_inputs(fov, size, usable):
    need(isinstance(size, (list, tuple)) and len(size) == 2 and all((type(x) is int and x > 0 for x in size)), 'Positive integral actual viewport dimensions')
    need(type(fov) in (int, float) and math.isfinite(fov) and (1.0 < fov < 120.0) and (type(usable) in (int, float)) and math.isfinite(usable) and (0.0 < usable < 1.0), 'Finite bounded FOV and central frame fraction')

def evaluate(points, camera, forward, fov, size, usable):
    """Return analytical projection facts for every supplied point; this does not read a renderer."""
    _projection_inputs(fov, size, usable)
    need(isinstance(points, (list, tuple)) and bool(points), 'Nonempty complete point sequence required')
    for point in points:
        vec(point)
    camera = vec(camera)
    f, r, up = basis(forward)
    aspect = size[0] / size[1]
    tan_h = math.tan(math.radians(fov) * 0.5)
    tan_v = tan_h / aspect
    rows = []
    for i, p in enumerate(points):
        delta = [p[k] - camera[k] for k in range(3)]
        depth = dot(delta, f)
        x = dot(delta, r)
        y = dot(delta, up)
        nx = x / (depth * tan_h) if depth > 0 else None
        ny = y / (depth * tan_v) if depth > 0 else None
        rows.append((i, depth, nx, ny))
    positive = all((row[1] > 0 for row in rows))
    depth_margin = all((row[1] >= 100.0 for row in rows))
    valid = [row for row in rows if row[2] is not None]
    maximum = max((max(abs(row[2]), abs(row[3])) for row in valid), default=None)
    inside = positive and depth_margin and (len(valid) == len(points)) and (maximum is not None) and (maximum <= usable + 1e-08)
    worst = max(valid, key=lambda row: max(abs(row[2]), abs(row[3]))) if valid else None
    return {'status': 'ALL_NATIVE_VERTICES_INSIDE_SAFE_FRAME' if inside else 'REFUSED_NATIVE_VERTEX_FRAMING', 'vertices': len(points), 'actual_viewport_dimensions': size, 'horizontal_FOV_degrees': fov, 'aspect': aspect, 'usable_central_frame_fraction': usable, 'required_margin_each_side_fraction': (1.0 - usable) * 0.5, 'strictly_positive_camera_depth_for_every_vertex': positive, 'required_conservative_depth_margin_cm': 100.0, 'conservative_depth_margin_satisfied': depth_margin, 'actual_native_near_plane_direct_readback': False, 'minimum_camera_depth_cm': min((row[1] for row in rows)), 'maximum_abs_normalized_device_coordinate': maximum, 'NDC_minimum_maximum_XY': [[min((row[k] for row in valid)) for k in (2, 3)], [max((row[k] for row in valid)) for k in (2, 3)]] if valid else None, 'worst_vertex': {'index': worst[0], 'world_position_cm': points[worst[0]], 'depth_cm': worst[1], 'NDC_XY': [worst[2], worst[3]]} if worst else None, 'all_vertices_included_no_bone_or_capsule_filter': True, 'occlusion_contact_or_final_art_qualified': False}

def fit(pose, outward, fov, size, usable=0.88, *, expected_vertex_count=10707):
    """Fit every posed vertex inside the central frame fraction with the retained depth policy."""
    _projection_inputs(fov, size, usable)
    points = world_vertices(pose, expected_vertex_count=expected_vertex_count)
    minimum = [min((p[k] for p in points)) for k in range(3)]
    maximum = [max((p[k] for p in points)) for k in range(3)]
    target = [(a + b) * 0.5 for a, b in zip(minimum, maximum)]
    outward = unit(outward)
    forward = [-x for x in outward]
    f, r, up = basis(forward)
    tan_h = math.tan(math.radians(fov) * 0.5)
    tan_v = tan_h / (size[0] / size[1])
    required = []
    for p in points:
        q = [p[k] - target[k] for k in range(3)]
        z = dot(q, f)
        required.extend((abs(dot(q, r)) / (usable * tan_h) - z, abs(dot(q, up)) / (usable * tan_v) - z, -z + 100.0))
    minimum_distance = max(required)
    distance = math.ceil((minimum_distance * 1.01 + 0.1) * 100.0) / 100.0
    camera = [target[k] + outward[k] * distance for k in range(3)]
    proof = evaluate(points, camera, forward, fov, size, usable)
    need(proof['status'] == 'ALL_NATIVE_VERTICES_INSIDE_SAFE_FRAME', 'Derived native camera failed finite projection gate')
    return {'camera_cm': camera, 'target_cm': target, 'horizontal_FOV_degrees': fov, 'direction_from_target': outward, 'distance_cm': distance, 'minimum_distance_for_all_vertices_cm': minimum_distance, 'safety_over_analytic_minimum': '1 percent plus0.1cm, rounded up0.01cm', 'actual_world_AABB_minimum_maximum_cm': [minimum, maximum], 'world_vertices_f64_json_SHA256': hashlib.sha256(json.dumps(points, separators=(',', ':'), allow_nan=False).encode()).hexdigest(), 'derived_projection': proof}

def verify_actual_view(pose, viewport, usable=0.88, *, expected_vertex_count=10707):
    """Project every posed vertex using a caller-observed horizontal-FOV, Z-up, zero-roll view."""
    need(isinstance(viewport, dict) and viewport.get('perspective') is True and (viewport.get('lit') is True), 'Actual native perspective Lit viewport required')
    pitch, yaw, roll = vec(viewport['rotation_pitch_yaw_roll'])
    need(abs(roll) < 1e-06, 'Actual zero-roll look-at camera required')
    pitch = math.radians(pitch)
    yaw = math.radians(yaw)
    forward = [math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)]
    return evaluate(world_vertices(pose, expected_vertex_count=expected_vertex_count), viewport['location_cm'], forward, float(viewport['fov']), [viewport['viewport_width'], viewport['viewport_height']], usable)
