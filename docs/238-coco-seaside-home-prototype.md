# Slice 238 — Coco's seaside home prototype

## Outcome

The former generic `home2` shell is now an enlarged 11×8, two-floor named residence designed around Coco's hotel work and private life.

- The ground floor contains a receiving room/hotel office, kitchen and dining room, and a fabric-rich hotel-linen workroom.
- The upper floor contains Coco's furnished bedroom, a guest bedroom/reading room, a shared bathroom, and a stair landing.
- Real wall segments, arches, and doors divide the plan; large furniture compositions fill rooms without blocking the entrance-to-stair route.
- The interior camera fits the larger utility-driven bounds instead of forcing the home into the old 9×7 box.
- Four PixelLab compositions replace clusters of disposable small props: office/library, linen workroom, guest bed/study, and Coco's bedroom suite.

This slice deliberately stops at a **named-home visual and navigation prototype**. The attempted live relocation of a resident was rejected after long-run monitoring exposed household-logistics failures; details are recorded below.

## PixelLab asset-factory receipt

Mode: `create_1_direction_object`, top-down, 128 px, four-frame review pack. All four candidates were promoted and used directly.

Prompt:

> cohesive resident-specific furniture compositions for a sophisticated lived-in French Atlantic townhouse, low top-down pixel art game sprites, transparent background, warm walnut and oak, cream linen, faded burgundy, muted teal and brass, dense believable personal detail, natural window light, readable at 48 pixel tile scale, no people, no text

| Saved asset | PixelLab object | Final use |
|---|---|---|
| `game/assets/art/furn/coco_hotel_library.png` | `61b69960-0ab0-4fcc-b652-91e70f3b5085` | hotel office and receiving-room library |
| `game/assets/art/furn/coco_linen_atelier.png` | `79ba1e42-cbb4-4205-8a59-8ee1ce006fda` | linen/sewing workroom |
| `game/assets/art/furn/coco_guest_bedroom.png` | `2e9b7a90-5c37-4ca9-a603-a7a9a0fc12db` | guest bedroom and reading suite |
| `game/assets/art/furn/coco_bedroom_suite.png` | `11daf166-511b-4ca3-b4eb-aeb3ae86864e` | Coco's private bedroom |

Review pack: `00e67d8c-ce0c-4033-96b0-1d88fe688f8b`.

## Evidence

- [Ground floor: office, receiving room, kitchen, dining, and linen workroom](media/238_coco_home_1f.png)
- [Upper floor: guest room, Coco's bedroom, bathroom, and landing](media/238_coco_home_2f.png)

## Navigation and monitoring

- The first ground-floor draft trapped the stair between the large sewing composition, a plant, and a partition. The long-run seed-1 failure exposed this; the accepted layout opens a direct landing passage.
- Accepted navigation has 21 connected open cells on 1F and 27 on 2F. The street door and stair endpoints share one connected component, and the authored room positions are reachable.
- A live two-resident trial reduced production 1,977 → 1,805, increased shortages 438 → 544, dropped supply invariant #40 to 9/12, and reduced aid coverage below quorum. It was rejected.
- A single-resident trial still produced hunger-floor violations after sleeping or returning home. A pantry-delivery experiment also failed to remove the problem cleanly and was removed rather than weakening invariant #1 or conjuring free food.
- Accepted state leaves agent home authority and every economic interaction unchanged. N=12, seeds 1–12, 60 days is byte-identical to Slice 237: hard 12/12, every soft invariant 12/12, all 21 event classes live, goldens 12/12, determinism 3/3.
- `space_test` passes with zero failures. DetGate passes 16/16 across default, faction, betrayal, and free-rider tracks; data fingerprint is `3853483244`.
- The pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Integration constraint

Turning this prototype into an actively occupied simulation home requires a general household-logistics slice, not a visual exception:

1. interior households need an authoritative, paid restocking route that remains safe outside market opening hours;
2. home-meal and sleep journeys must include complete cross-floor travel horizons;
3. social recovery must not collapse when a resident spends evenings behind a private portal;
4. only after those contracts pass the existing zero-starvation and supply gates should a resident's `spatial_address` move here.

## Ordered continuation

Per the requested priority, the next slices are:

1. beach civic-life district;
2. courtyard access language;
3. street-corner activity props.
