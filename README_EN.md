# Living Town · 小镇有灵

A pixel life simulation where you can become a resident or watch a town unfold.

Residents work, eat, make friends, and remember promises, rumors, and disputes. Choose someone to play, explore their neighborhood, or use the observer panels to follow relationships, trade, and civic decisions.

[中文](README.md) · [Development notes](docs/README.md)

![In-engine gameplay tour](docs/media/gameplay-tour.gif)

[Watch the full MP4](docs/media/gameplay-tour.mp4) · [Recording and chapters](docs/249-gameplay-tour.md) · [Town blueprint](analysis/247/neighborhood-blueprint.png)

## Latest changes

- Rebuilt coastal streets, courtyards, passages, tree belts, and gardens using detailed PixelLab assets.
- Distinct residential, commercial, civic, and workshop facades, with entrances aligned to the street.
- Irregular room plans, partitions, accessible stairs, and a camera that follows the character indoors and outdoors.
- Inspectable civic policy, election, and cooperative bank impact receipts.

## Life in town

- Meet needs, pursue wishes, work, and rest as a resident.
- Talk, give gifts, arrange meetings, spread rumors, and resolve conflicts.
- Explore the market, library, baths, workshop, homes, and waterfront.
- Inspect resident states, stories, the transaction ledger, and civic policies.

This is a playable prototype under active development. Some buildings are scenery. The recording uses the logic backend: player movement and doors are driven through real gameplay APIs, followed by explicitly labelled observer chapters. It is a feature tour, not proof of every mechanic or model response.

## Play

Use **Godot 4.6.2**, import `game/project.godot`, and press **F5** in the editor. Let the first asset import finish.

```bash
git clone https://github.com/ForTe13X/living-town.git
cd living-town
godot --editor --path game
```

Choose a resident in the default life mode. **No model or API key is required.** Local LLM and NobodyWho SLM backends are optional; model weights and extension binaries are distributed separately. See [backend setup](docs/03-LLM集成架构.md).

| Action | Controls |
| --- | --- |
| Walk | WASD / arrows / click ground |
| Interact / cycle target | E / Tab |
| Cancel / relationships | Q / R |
| Pause / speed | Space / 1–3 |
| Free will / choose resident | F / C |
| Save / load | F5 / F8 inside the game |

## Development

`game/` holds the Godot project, `tools/` contains audits and recording tools, and `docs/` preserves design and experimental notes. The simulation owns outcomes; optional models choose legal actions and supply dialogue.

```bash
python tools/lint_data.py
python tools/audit_coastal_plan.py
python tools/audit_neighborhoods.py
bash tools/ci.sh
```

On Windows, use `tools/run-godot-supervised.ps1` for local Godot checks. See the [recording guide](docs/249-gameplay-tour.md) to reproduce the tour. Reproducible bug reports, gameplay feedback, and PRs are welcome.

Code is MIT licensed. Art includes CC0 derivatives and PixelLab-generated assets; see [credits](docs/09-美术资产与版权.md), [coastal asset provenance](docs/246-coastal-circulation-pixellab-camera.md), and [facade orientation notes](docs/248-blueprint-frontages.md).
