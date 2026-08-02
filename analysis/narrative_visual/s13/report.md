# S13 narrative view evidence

Date: 2026-08-02

Source baseline: `ef50720` (`feat: add role-filtered narrative view contract`)

## Outcome

- `WebMazeGraph`, `RolePOVCard`, and six code-native glyphs consume only the S06 ten-field snapshot.
- One synthetic authority state projects two roles at the same `square` node into different visible subgraphs and receipt cards.
- The hidden node ID, hidden claim prose, and hidden fragment body are absent from both snapshots and the rendered node trees.
- All 15 glyph pairs differ at both 64 px (1x) and 32 px (0.5x).

## Commands and results

Headless structure/privacy gate:

```powershell
C:\Users\yp\AppData\Local\Programs\Godot\4.6.2-stable\Godot_v4.6.2-stable_win64_console.exe --headless --path game res://scenes/narrative/s13_visual_test.tscn -- --logic-only --no-output
```

Result: `S13 VISUAL: PASS (20 checks, 0 fail)`.

Framebuffer visual/pixel gate and artifact generation:

```powershell
C:\Users\yp\AppData\Local\Programs\Godot\4.6.2-stable\Godot_v4.6.2-stable_win64_console.exe --path game res://scenes/narrative/s13_visual_test.tscn -- --out E:\Documents\Dev\June\26th\analysis\narrative_visual\s13
```

Result: `S13 VISUAL: PASS (59 checks, 0 fail)`, exit code 0.

Negative control (all six glyph classes forcibly rendered as `unknown`):

```powershell
C:\Users\yp\AppData\Local\Programs\Godot\4.6.2-stable\Godot_v4.6.2-stable_win64_console.exe --path game res://scenes/narrative/s13_visual_test.tscn -- --negative-control --no-output
```

Result: `S13 NEGATIVE CONTROL: RED as expected (30 gate failures)`, expected exit code 7. The pre-implementation baseline also had none of the three S13 component files, so it could not satisfy the gate.

## Rendered evidence and measurements

| Artifact | Pixel size | Visual check |
|---|---:|---|
| `role_pair.png` | 1200 x 650 | Same `square` node is explicit on both cards; role, receipt, fragment, request, status, and web counts visibly differ. |
| `maze.png` | 1200 x 620 | Left role sees 3 nodes / 2 links; right role sees 4 nodes / 3 links, a different route and blocked current-node glyph. |
| `glyph_sheet.png` | 1000 x 360 | Fragment, receipt, request, blocked, traversed, and unknown remain recognizable in both rows. |

Pixel criteria (RGB/RGBA value comparison, not alpha-only `getbbox()`):

- role-card pair: 3,998 differing pixels; threshold > 400.
- maze pair: 11,465 differing pixels; threshold > 400.
- 64 px glyphs: every pair nonzero; minimum pair difference 638 pixels (`receipt` vs `request`).
- 32 px glyphs: every pair nonzero; minimum pair difference 161 pixels (`receipt` vs `request`).
- Full pair matrix: `metrics.json`.

The three PNGs were opened at original resolution after generation. No clipping, overlap, missing label, blank framebuffer, or half-scale glyph collapse was observed.

## Detection envelope

detects:

- a role pair at the same node collapsing to the same visible-node or receipt-ID projection;
- hidden fixture node/prose/body entering either snapshot or the component node tree;
- an eleventh `claim_prose` field crossing into either component (both fail closed);
- any of the 15 glyph pairs becoming pixel-identical at either scale;
- the measured all-glyph collapse mutation (30/30 pair-scale gates red).

does_not_detect:

- semantic edge topology: S06 exposes edge IDs but not edge endpoints, so S13 cannot prove its ordinal web lines match authoritative connections;
- prose disguised inside a syntactically valid ID; that requires stronger S06 ID grammar or provenance validation;
- accessibility, color-vision variants, localization overflow, touch targets, or real-phone raster behavior;
- S16 compositor interaction, production state integration, replay, or authoring quality.

confidence:

- High for the rendered fixture, node-tree privacy assertions, and six glyph geometries (30 pair-scale comparisons plus one collapse mutant).
- Medium for generalized information-flow safety: one synthetic role pair and one extra-field mutant were exercised; valid-ID smuggling remains outside the gate.

## What the brief gets wrong or leaves underspecified

The requested "web maze graph" cannot reconstruct canonical edge topology from the current S06 ten-field contract: `visible_edges` contains IDs only, with no endpoints. This implementation intentionally draws a deterministic ordinal web from visible node order and edge count, while `route_hint` supplies the only meaningful path sequence. Reading `Sim`, world data, or author truth to recover endpoints would violate the S13 boundary. A later contract revision must add role-filtered endpoint pairs if canonical topology is required.

The visual gate cannot run under this project's `--headless` dummy renderer because it exposes no framebuffer texture. The test therefore has a finite 20-check headless structure mode and a separate real-framebuffer 59-check visual mode; treating a dummy framebuffer as a successful screenshot would be a false green.
