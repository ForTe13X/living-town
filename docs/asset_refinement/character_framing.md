# Complete-character camera framing

`tools.unreal.character_framing` is a pure host utility extracted from the complete-body native review. It transforms every native posed render vertex to world centimeters and fits a horizontal-FOV camera around the complete set. It imports only the Python standard library and performs no file, editor, graphics or asset operations.

```python
from tools.unreal.character_framing import fit, verify_actual_view

camera = fit(
    pose, [1, -1, 0.15], 45.0, [viewport_width, viewport_height],
    expected_vertex_count=verified_mesh_snapshot["vertices"],
)
# Apply through the caller's qualified adapter, then read back its actual view.
projection = verify_actual_view(
    pose, actual_viewport,
    expected_vertex_count=verified_mesh_snapshot["vertices"],
)
```

Use a separately verified mesh count, never `len(pose["component_space_positions_cm"])` as a substitute. The default stays 10,707 for the existing character. A mismatch refuses instead of trimming, sampling, filtering by bone, or substituting a capsule. Pose schema remains `READ_ACTUAL_CPU_SKINNED_POSE_EXPLICIT_EVALUATION`, with `component_space_positions_cm` and `component_to_world` translation, scale and XYZW quaternion. Scale, then rotation, then translation are applied once.

The math assumes centimeters, Z-up, horizontal FOV, a zero-roll camera and a caller-verified editor projection policy. The caller must validate the relevant axis policy and unpiloted, non-stereo view, and disclose any unobserved view modifiers. The central-frame fraction defaults to 0.88. The fixed 100 cm depth margin is a conservative model policy, not an observed native near plane. Returned status describes analytical inclusion; it does not prove actual clipping, visibility, contact, artistic quality or performance. Actual captures and exact adapter restoration remain necessary.

The source's camera padding, rounding, schema fields and arithmetic are retained. Dot products explicitly accumulate left to right to preserve the actually executed UE Python 3.11 results on newer hosts. Python 3.12 changed float `sum()` behavior; a direct copy otherwise produced a one-ULP projection difference. See the [Python 3.12 documentation](https://docs.python.org/3.12/library/functions.html#sum). This is compatibility with the recorded calculation, not a claim of greater numerical accuracy.

API changes are an explicit `expected_vertex_count` keyword on `fit` and `verify_actual_view`; `world_vertices` uses the same name in place of the old `required_count` keyword. Default outputs are unchanged for the retained character. Validation now rejects malformed/nonfinite inputs before arithmetic, nonpositive or noninteger counts, nonintegral viewport dimensions instead of truncating them, and nonboolean viewport flags.

Synthetic tests run without external assets or absolute paths:

```text
python -B -m unittest discover -s tools/tests -p test_character_framing.py
```

The preparation also contains a separate, non-repository replay against all seven retained body poses/fits and 21 capture receipts. On the tested Windows Python 3.11 and 3.12 runtimes, the proposal reproduces every stored world-coordinate, camera and projection result exactly, covering 42 before/after capture states. No geometry fixture is shipped here. That CPU replay does not mean this new module has run in the native editor; adapters must bind and qualify the adopted bytes before making that claim.
