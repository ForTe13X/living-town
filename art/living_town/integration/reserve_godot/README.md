This isolated Godot 4.6 project consumes the portable GLB package. It does not modify the model or the main game, and supplies no collision or navigation authority. The expected amenity IDs come from the source-bound native manifest rather than fixed counters.

The harness validates reserve roots, room/furnishing IDs, metric placements, shared woodland mesh resources and actual tree transforms, local cover visibility over multiple frames, embedded PBR dependencies, bridge endpoints, and four local-origin prefab types. Its material adapter preserves source vertex-color multiplication and transparent glass. Authored near/far woodland mesh choices remain static; this harness does not implement runtime LOD or measure gameplay performance.

Node identity uses explicit consumer-only source-index and mesh-index metadata stamped on `GLTFState.get_nodes()` before scene generation. Godot carries those stamps to generated nodes and preserves them when converting importer meshes. This avoids both sanitized display names and the stale original mesh pointers retained by Godot 4.6.2's `get_scene_node()`. The consumer checks the complete source/actual node bijection, unique actual mesh instances, mesh-index stamps and every mapped mesh's world transform before testing room ancestry, shared mesh resources and bridge geometry. It does not assume glTF extras automatically become runtime metadata.

When the coordinator grants the serial heavy-job slot, run the following with the actual Godot executable and completed export paths:

```powershell
python art/living_town/integration/reserve_godot/run_consumer.py --godot 'D:/path/to/Godot_console.exe' --assets 'C:/absolute/path/game_assets_reserve' --native-manifest 'C:/absolute/path/town_manifest.json' --evidence 'C:/absolute/path/reserve_consumer_evidence' --capture
```

The runner invokes a parser gate, a headless logical process, then a separate real renderer, one at a time. It uses the project settings of six worker threads and single-threaded imports, and caps frame rate at 30. `GLTFDocument` reads the package in place; no large asset copy or editor import is needed. Omit `--capture` for the logical checks only.

Outputs are `logical_report.json`, `render_report.json`, `runner_report.json`, process logs and four PNGs in `captures`: reserve overview, trailer park, local trailer cutaway and woodland bridge. Reports bind the source/export/GLB and PNG hashes. A successful framebuffer check is not a visual sign-off: open all four actual PNGs and record a separate review. Run without `--headless` for captures; the harness rejects dummy framebuffers.

The final source-bound Godot 4.6.2 run passes 57 logical and 66 renderer checks with clean stderr. All 20,646 source nodes and 19,353 unique runtime mesh instances map correctly; 3,500 trees retain 46 shared mesh resources. All four actual PNGs were separately opened and accepted in the [combined 19-image review](../../evidence/reserve_visual_review.json). The tested optimized town is 4,976,516 expanded triangles and 321,050,860 bytes. [Release ZIP](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/LivingTown_Reserve_Delivery.zip) and [checksum sidecar](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/LivingTown_Reserve_Delivery.zip.sha256) have fixed release paths; external package/ZIP-verification receipts supply final archive acceptance.

Direct engine arguments after `--` are `--asset-dir=ABS`, `--native-manifest=ABS`, `--report=ABS` and optional `--capture=ABS`. Reports and screenshots are generated only when the consumer is explicitly executed.
