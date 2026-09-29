# 245 — Reference-led coastal architecture

The supplied Aranya references inform a consistent terracotta-and-stucco exterior kit within the existing top-down game camera. This is an adaptation to the game renderer, not a reproduction of the aerial perspective.

- Seven functional buildings now compose rear ranges, side wings, planted light courts and paired front wings around a central passage.
- Forty-four decorative lots use ivory/sand facades, hipped tile roofs, shutters, balconies and commercial awnings. Windmill and beach utility/recreation sprites retain their silhouettes.
- The chapel and civic building have clock towers; the market hall has a glazed roof strip.
- Three connected paved spaces extend the civic, market and garden composition. Main street widths are increased through presentation data.
- Navigation footprints, functional entrances, interior spaces and simulation state are preserved. Courtyard planting is exterior scenery, not new accessible interior space.

Implementation: `game/scripts/CoastalArchitecture.gd`, `game/scripts/WorldView.gd`, and `game/assets/art/houses/lots.json`.

Validation: lint_data and audit_map pass (1,986 walkable cells); space_test reports 0 fail; exterior_visual_test reports 0 failures, 50 facade instances and seven roofed buildings. Day and night renders were inspected at town and market scales. Supervised final render runs both passed with stable source identity. The initial render receipt detected output-file source drift; final captures were written outside the checkout and copied in after validation.

Evidence: `analysis/245/day/{town,market,coast}.png` and `analysis/245/night/{town,market,coast}.png`.
