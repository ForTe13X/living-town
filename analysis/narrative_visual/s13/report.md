# S13 narrative view evidence

Date: 2026-08-02

Component source baseline: `ef50720` (`feat: add role-filtered narrative view contract`)

S13R media-hardening baseline: `c1791b044696dcc8276d688bc644b1e6b6226fdb`

Source receipt: `source.receipt.s13r.review_media.c1791b044696`

## Outcome

- `WebMazeGraph`, `RolePOVCard`, and six code-native glyphs consume only the S06 ten-field snapshot.
- One synthetic authority state projects two roles at the same `square` node into different visible subgraphs and receipt cards.
- The hidden node ID, hidden claim prose, and hidden fragment body are absent from both snapshots and the rendered node trees.
- All 15 glyph pairs differ at both 64 px (1x) and 32 px (0.5x).
- Every exported review PNG permanently carries `SYNTHETIC COMPONENT REVIEW · NOT GAMEPLAY`; the static reel preserves that mark in all three holds and repeats `NOT GAMEPLAY` in MP4 title/comment metadata.
- This evidence is a synthetic static component review. It is not gameplay capture and is not production integration evidence.

## Commands and results

The reproducible entry point accepts explicit Godot, ffmpeg, and ffprobe commands and runs the whole chain:

```powershell
& analysis/narrative_visual/s13/render_review_media.ps1 `
  -RepoRoot . -Godot godot -Ffmpeg ffmpeg -Ffprobe ffprobe -Uv uv
```

Executed sub-gates:

- headless structure/privacy: `S13 VISUAL: PASS (21 checks, 0 fail)`;
- real OpenGL framebuffer render: `S13 VISUAL: PASS (63 checks, 0 fail)`;
- all-glyph-collapse negative control: `S13 NEGATIVE CONTROL: RED as expected (30 gate failures)`, expected exit code 7;
- live media/source gate: `PASS`, zero issues;
- exact-artifact plus three mutation tests: 4/4 PASS.

The live gate is written to `media_gate.json` and byte-compared against a fresh probe by `test_review_media.py`; the artifact is not accepted on shape or self-attestation alone.

## Rendered evidence and measurements

| Artifact | Pixel size | Visual check |
|---|---:|---|
| `role_pair.png` | 1200 x 650 | Same `square` node is explicit on both cards; the permanent bottom-band watermark has 1,200 accent pixels in one row and 1,231 light text pixels. |
| `maze.png` | 1200 x 620 | Left role sees 3 nodes / 2 links and right role sees 4 nodes / 3 links; the permanent watermark has the same measured pixel proof. |
| `glyph_sheet.png` | 1000 x 360 | All six glyphs remain recognizable at both scales; the permanent watermark has 1,000 accent pixels in one row and 1,231 light text pixels. |
| `component_reel.mp4` | 1280 x 768, 15 s | Three five-second static holds. Frames probed at 2.5, 7.5, and 12.5 seconds each retain the watermark. This is not gameplay. |

MP4 metadata is explicit:

- title: `SYNTHETIC COMPONENT REVIEW · NOT GAMEPLAY`;
- comment: `STATIC REVIEW REEL · NOT GAMEPLAY · three five-second holds from watermarked S13 component PNGs`.

`media_manifest.sha256` has a schema header, the full baseline main commit, the source receipt ID, the exact watermark text, and hashes for all four media files, `metrics.json`, the five component/test sources, the three S13R builder/verifier/test sources, and this report (14 entries total). The video was assembled only from the already verified PNGs; no intermediate frame is treated as independent evidence.

Pixel criteria (RGB/RGBA value comparison, not alpha-only `getbbox()`):

- role-card pair: 3,998 differing pixels; threshold > 400.
- maze pair: 11,465 differing pixels; threshold > 400.
- 64 px glyphs: every pair nonzero; minimum pair difference 638 pixels (`receipt` vs `request`).
- 32 px glyphs: every pair nonzero; minimum pair difference 161 pixels (`receipt` vs `request`).
- PNG watermark gate: full-width accent line plus at least 220 cream text pixels; measured text count is 1,231 in each source PNG.
- Video gate: exact 1280 x 768 resolution, 15.00 s duration, exact title, `NOT GAMEPLAY` comment, and watermark pixels present in each hold.
- Full pair matrix: `metrics.json`.

The three PNGs were opened at original resolution after generation. No clipping, overlap, missing label, blank framebuffer, or half-scale glyph collapse was observed.

## Detection envelope

detects:

- a role pair at the same node collapsing to the same visible-node or receipt-ID projection;
- hidden fixture node/prose/body entering either snapshot or the component node tree;
- an eleventh `claim_prose` field crossing into either component (both fail closed);
- any of the 15 glyph pairs becoming pixel-identical at either scale;
- the measured all-glyph collapse mutation (30/30 pair-scale gates red);
- an erased PNG watermark band, missing MP4 `NOT GAMEPLAY` metadata, or any manifest/source hash drift;
- media detached from the declared baseline main commit and source receipt.

does_not_detect:

- semantic edge topology: S06 exposes edge IDs but not edge endpoints, so S13 cannot prove its ordinal web lines match authoritative connections;
- prose disguised inside a syntactically valid ID; that requires stronger S06 ID grammar or provenance validation;
- accessibility, color-vision variants, localization overflow, touch targets, or real-phone raster behavior;
- S16 compositor interaction, production state integration, replay, or authoring quality.
- animation or input responsiveness: the reel is deliberately a static component review, not a gameplay recording;
- watermark legibility after an unknown future transcode; the gate covers the committed source reel only.

confidence:

- High for the bound static review media, watermark/metadata probes, rendered fixture, node-tree privacy assertions, and six glyph geometries (30 pair-scale comparisons plus one collapse mutant).
- Medium for generalized information-flow safety: one synthetic role pair and one extra-field mutant were exercised; valid-ID smuggling remains outside the gate.

## What the brief gets wrong or leaves underspecified

The requested "web maze graph" cannot reconstruct canonical edge topology from the current S06 ten-field contract: `visible_edges` contains IDs only, with no endpoints. This implementation intentionally draws a deterministic ordinal web from visible node order and edge count, while `route_hint` supplies the only meaningful path sequence. Reading `Sim`, world data, or author truth to recover endpoints would violate the S13 boundary. A later contract revision must add role-filtered endpoint pairs if canonical topology is required.

The visual gate cannot run under this project's `--headless` dummy renderer because it exposes no framebuffer texture. The test therefore has a finite 21-check headless structure mode and a separate real-framebuffer 63-check visual mode; treating a dummy framebuffer as a successful screenshot would be a false green.
