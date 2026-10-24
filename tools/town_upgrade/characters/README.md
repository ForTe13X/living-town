The refined residents use MakeHuman's CC0 anatomical base, age/gender macro
targets, weight data, authored tailored system outfit and alpha-textured hair,
adapted by this repository's own loader, relaxed-pose conversion, garment fitting,
original aprons, persona palettes, UV/PBR texturing and named-joint animation. The
MakeHuman application and its AGPL program code are not imported or vendored.

The official asset license explicitly covers the base mesh, targets, clothes,
poses and other graphical data:

- <https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md>
- <https://static.makehumancommunity.org/mpfb/faq/build_other_chargen.html>

Only the source OBJ, Asian male/female young/old/child macro targets, rig/weight
graphical data and exact upstream license texts
are vendored in `vendor/makehuman`. Every file is verified against the SHA-256
values in `vendor/makehuman/provenance.json` before a character build. That file
records the retrieval date and original URLs; the build uses local verified data
and never fetches an updated master branch silently. Both weight and rig files
also declare `CC0` in their own metadata. The OBJ has an explicit CC0 header.

`vendor/system_assets` contains selected members of the official CC0 system
asset archive. Its provenance records the exact archive URL, member path,
SHA-256 and byte count of each OBJ/MHCLO/material/strand texture. Every MHCLO
also has an explicit CC0 release header. The independent fitter applies native
three-vertex barycentric mappings and anatomical-axis offsets to the morphed
unposed base before transforming both cloth and skin into the relaxed rest
pose. The authored outfit supplies continuous collar, cuffs, belt and pockets.
The connected casual outfit's shirt and trousers retain complete authored UV
islands when receiving persona colors. Their shared waist follows the original
closed seam, so anatomical adaptation cannot move a height-based palette cut
through the shirt hem. This changes material assignment without moving source
vertices or changing their atlas coordinates, topology or skin weights.
The original asset author's body mask removes occluded skin. No generated
radial envelope or stitched shoulder patch is used in the production mesh.
Hair retains the authored strand opacity and UVs with baked persona-color
derivatives; glTF materials use alpha masking and two-sided cards.
The original apron is one closed, continuous cloth surface with a subdivided
pocket sharing its geometry/weights. An optional `ApronDrape` control follows
the forward leg and seated lap without splitting opposing thigh influences
through the center seam; `ApronHem` bends the lower edge over the knees. The 15
anatomical controls remain the core contract.

Official asset table:
<https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html>
`fetch_system_assets.py` retrieves only selected members over HTTP byte ranges;
it is a separate preparation step, never invoked by a character build.

Build under the root engine supervisor, with Blender restricted to CPU and six
threads:

```powershell
& $Blender --background --factory-startup --threads 6 --python tools/town_upgrade/characters/build.py -- --output "F:/Living Town/2026-10-20_Refined_Town/characters" --texture-library "F:/Living Town/2026-10-20_Refined_Town/character_pbr/library_manifest.json" --game-assets game/assets/characters3d --render-review
```

Use `--personas aria,ben` for hero review before the full 25-character batch.
The output contains engine-independent GLBs with seven native animation clips,
packed Blender source files, baked texture images, front/three-quarter/side/back
review renders and a provenance report. Hero subsets also render four stride
phases and every furniture/social pose, so shoulder, knee, apron and seat
deformation can be inspected before a whole batch. Source checks verify the
five authored outfit openings, body-mask coverage, normalized skin influences,
finite fits across all 25 identities and conventional leg silhouette. Render
inspection remains required: these numerical checks do not prove freedom from
every pose-dependent intersection.
`game/data/town3d/characters.json` is the
stable actor manifest; character height, persona identity, feet origin and
negative-Z forward direction are explicit.

`TownCharacter3D.gd` renders the same assets with replay-seekable named joints
and continuous skinning. Walking uses a 0.78-second presentation clock;
`ag.render_motion_phase` can override it for exact visual capture. Canonical
movement, furniture access, identity, needs and simulation time are untouched.
Godot 4 absolute bone-pose semantics preserve each local rest transform before
composing the same XYZ quaternion increments used by the native clips.
After staging, the root engine supervisor can run `runtime_probe.gd` headlessly
to check all 25 identities and seven poses for preserved bone offsets, finite
unit rotations, idle pelvis rest basis and complete skin coverage. The source
test suite does not substitute for this actual engine check.

The character texture stage consumes the repository's dedicated refinement
workflow: verify CC0 source hashes, prepare registered maps with a documented
linear-light palette bake, use conventional Blender/glTF PBR nodes, then verify
the actual exported embedded pixels and original UV registration independently.
`prepare_textures.py` produces 2048-square skin and garment maps from the native
2048 sources. The authored skin atlas supplies pores, lip color, nail and facial
variation; it is not replaced by uniform procedural color. The original shirt
and jeans diffuse, tangent normal and AO maps retain seams, buttons, cuffs,
pockets and denim detail on their exact authored UVs. No eight-times UV tiling
is applied to these registered atlases. Iris geometry/maps and alpha eyebrow
and lash meshes also fit through native MHCLO mappings; primitive eyes/brows
and the old lip stripe are omitted.

Skin and eye sources do not supply independent measured roughness/normal maps.
Their roughness values are explicit artistic finishes; the garment normal and
AO are genuine upstream authored maps. These are not relabeled as calibrated
scan measurements. Albedo is sRGB; normal/AO data remain Non-Color. Head
portraits use enough pixels for facial inspection, in front/three-quarter views
under both neutral and warm summer light. Garment close-ups expose the actual
seams and surface finish. Pixel checks establish export fidelity, not realism,
style matching or artistic acceptance.

Prepare before the supervised Blender build, and pass its library explicitly:

```powershell
python tools/town_upgrade/characters/prepare_textures.py --output "F:/Living Town/2026-10-20_Refined_Town/character_pbr_v10_hero" --personas aria,ben --size 2048
# Add --texture-library ".../character_pbr_v10_hero/library_manifest.json" to build.py.
python tools/town_upgrade/characters/verify_textures.py --build ".../characters_lookdev_v10" --report ".../character_pbr_v10_verification.json"
```

The build keeps fallback accessory textures at the separate 512 setting and
purges each completed resident's unused image/material datablocks, bounding
memory during the full roster build. Every model and packed source retains its
own required maps; the prepared library and original source records travel in
the output. No inference process or external application is invoked here.

The final wardrobe uses three fitted authored outfits: collared shirt/jeans,
short-sleeve tee/jeans, and tee/bib overalls. `manifest.py` records every exact
choice. Original authored UVs and component boundaries keep overall bibs in
their intended fabric. CC0 laced brown shoes (`shoes01`) and white trainers
(`shoes05`) replace the provisional block shoes, using their authored skin
weights, registered diffuse maps and the leather shoe normal map. The fitted
shoe sole is translated to the origin ground plane; the adjustment is recorded.

The eye source has an intentionally transparent outer-cornea UV island with
blue placeholder RGB. Preparation preserves its RGBA coverage, and the eye
material uses alpha masking with single-sided geometry; a source-pixel regression
guards against exposing that placeholder over the iris. Embedded export checks
compare alpha as well as color and verify each material's culling semantics.

Hero review also includes a separate 0.462 m chair and ground reference. It is
created after source/model export, never included in the game asset, and places
the actor using the runtime floor offset and fixture-derived hip height. Two
views and an evaluated-mesh contact JSON expose sole gaps and clothing clearance
against a metric seat. Portrait framing follows each resident's stature so
taller heads remain visible at the same inspection scale.

Aprons, straps and pockets use Poly Haven's CC0 `rough_linen` photographed
diffuse, OpenGL normal and packed ARM source. Exact source hashes, upstream
metadata, authors (colormass photography / Rico Cilliers processing) and license
URL are stored separately in `vendor/polyhaven_rough_linen`; these are not
MakeHuman assets. Preparation retains source luminance under the cream identity
palette and extracts authored AO/roughness from ARM red/green. Surface UVs use
the source's measured 0.270708139 x 0.271299988 m repeat, including resident
stature and strap length; the normal strength is restrained to 0.18. Export
verification compares embedded roughness/AO channels and cloth UV density as
well as the registered facial and outfit atlases.

Seated leg pitch is solved from each fitted model's hip/knee/ankle and actual
shoe-sole metrics. Counterturned shins keep the feet level while the pelvis
stays tied to the fixture. The native feet-origin frame and the runtime's
0.025 m presentation offset preserve identical world hip/sole geometry; the
offset is compensated once in local hip height. A localized `SeatContact`
trouser morph compresses the measured seat contact region without changing its
topology, UVs or skin weights. Standard glTF `weights` channels activate it in
Sit/Soak and reset it in the other five clips; the Godot actor and controlled
occlusion copy use the same values. The correction is bounded to 0.040 m posed
displacement and reports infeasible fits instead of increasing the cap silently.
The thicker workwear has a measured 5 mm world hip allowance, shared by both
coordinate frames. Dou uses a documented level-thigh child pose with naturally
dangling feet on an adult chair; his anatomy is not stretched to force adult
floor contact. Metric hero review includes him before full-cast acceptance.

Combined outfits are partitioned by their verified authored UV islands before
fitting, rather than by a world-height cut. The shirt/trouser boundary follows
the original closed waist seam while source coordinates, UV corners, topology
and skin weights stay intact. Material-role regressions cover every affected
resident and different body heights. After changing a garment factory, render
an actual hero waist close-up and motion pilot before rebuilding all 25.
