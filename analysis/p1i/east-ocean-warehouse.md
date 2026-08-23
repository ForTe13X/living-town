# P1-i — East Ocean playable warehouse

Status: candidate tree verified locally on 2026-08-12/13; golden/model-path/complement anchors were deliberately not rebaked.

## Purpose and contract

P1-i closes the visible-space gap behind the East Ocean CargoManifest slice. The dock door at town `[57,8]` now connects bidirectionally to a real `port_warehouse/1f` (`9x6`). A nearby player crosses the same portal that Probe inspects; warehouse collision uses its own nav grid, and the return door restores the player to the East Ocean dock. The room is presentation-only furniture—no new AI advert, job, production, RNG or economy authority.

The center board is a live view over `town_stock` (柴薪/豆子/口粮) and `cargo_status_for_node("port_dock")`. It does not cache or duplicate stock/manifest state. East-dock rendering also keeps carrier hull culling independent of deck culling and restores stock sacks to the east-facing port.

## Reusable verification

- Static contract: `python tools/audit_map.py` checks the exact portal, exterior walkable door cell, interior geometry/material and display-only furniture.
- Focused contract: `space_test.tscn` checks physical player entry, interior wall collision, walkable rug and return; player UI/save/P1-a/P1-b/P1-c/P1-g scenes remain green.
- Player-position render: `LT_RT=require LT_RT_RUNNER=docker LT_RT_SPACE=port_warehouse LT_RT_PLAYER_POS=57,8 LT_RT_OUT=<dir> bash tools/space_roundtrip.sh` captures East Ocean close-up → warehouse → East Ocean close-up. Metadata requires `player_entered=true` and `player_returned=true`.
- Visual negative control: repeat with `LT_RT_DRAW_SKIP=warehouse_status`, then run `python tools/assert_p1i_warehouse.py <on-dir> <off-dir>`. Pinned `gamecraft-runner:4.6.2` measured 56,048 changed pixels, bbox `(512,156)-(778,367)`, wholly inside the transformed board crop `(505,147)-(784,371)`.

## Presentation receipt

Two canonical player-position reference frames are checked into the reusable media pool; they are presentation receipts, not pixel goldens:

- [`docs/media/p1i_east_ocean_player.png`](../../docs/media/p1i_east_ocean_player.png), SHA-256 `2346D32D825F597BBC448D05283DF213E07E48879925216BBEC385A30AC4A60F`.
- [`docs/media/p1i_east_ocean_warehouse.png`](../../docs/media/p1i_east_ocean_warehouse.png), SHA-256 `8265F061BDC84CA44AE8772255645540CC967B07E7BED27A1BEB74C0E4DD2AE1`.

Both are project-generated at 1280×768 with Godot 4.6.2, `gamecraft-runner:4.6.2`, Mesa 23.2.1, seed 3 and tick 600; no external art or license enters the repository. Their rebuild source is `%TEMP%/p1i-player-warehouse-frames/{rt_town_before,rt_interior}.png` and the command above. The exterior composition shows the player, warehouse door, real ready-manifest vessel, cargo crates, stock hint and seven-action bar. The interior shows the same player beside the return door, live inventory bars and `柴薪×4·待卸` at day 3 noon. Both were manually inspected after machine gates passed.

The capture keeps the real player traversal receipts but restores view-only feed/selection state before the return frame, so the original full-map pixel identity tooth remains mandatory rather than being waived for player journeys. Portal clicks are also re-resolved through Sim's agent-aware access list; a nearby player cannot bypass owner-only stairs even though Probe remains free to inspect them. Full visual-gate CI is still skipped on unpinned GitHub GL; the local Docker route pins Mesa and uses tolerance zero.
