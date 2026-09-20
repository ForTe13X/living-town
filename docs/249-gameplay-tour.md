# Gameplay tour · 2026-09-20

[Full recording](media/gameplay-tour.mp4) · [Markdown GIF](media/gameplay-tour.gif) · [Chapter manifest](media/gameplay-tour.chapters.json)

The 81-second, 1280×768 recording captures the real Godot viewport at 10 frames per second, without audio. The 800-pixel GIF covers the same sequence at 3× speed. Both use the logic backend; this is a scripted feature tour, not a claim of manual play or complete behavioral coverage.

The player chapters start at Ben's actual location after 600 simulation ticks. Walking calls `Sim.life_step_toward`; doors and the public residence staircase call `Sim.life_portal`. Every step and transition is checked. The subsequent chapters are explicitly labelled observer inspections; changing the viewed room does not move the resident.

## Coverage

- Character movement, smooth follow camera, market street, café entrance and interaction menu.
- Residence entrance, actual ascent and descent, distinct floors, relationships and needs.
- Library, baths, workshop, hotel, warehouse and town hall interiors.
- Civic policy, cooperative bank, story and ledger panels.
- Street-facing terrace rows, gardens, coastal promenade and town overview, including evening lighting.

Panels show current simulation state; this recording does not execute a bank transaction or prove a full election cycle. Automated banking and governance tests cover those separate contracts. Model-generated conversation and Android performance are outside this capture.

## Findings and validation

The first walkthrough exposed an inaccessible residence staircase. The dining table and atelier furniture blocked both approaches from the hall; upstairs, a planter isolated a passage. The authored furniture layout now leaves a connected route and accessible seating. The generator preserves this fix, and the interior audit now includes both residence floors: nine floors pass.

The final take reports **0 failures, 810 frames**. Supervised receipt: `20260920T021657713Z_274d22a028fa4d56b379f219d9c73ac6`. Local optional NobodyWho extension-loading errors remain because its binary is not installed; the demonstration uses logic. An earlier take ended before completion and is not published.

The coastal, interior and map audits pass. CI now includes the coastal/interior audits plus banking, follow-camera and facade regression scenes. CI results belong to the PR's exact commit; this document does not substitute for them.

## Reproduce on Windows

Install Godot 4.6.2 and FFmpeg, import the Godot project once, then run from the repository root:

```powershell
./tools/record-gameplay-tour.ps1 -Godot C:/path/to/Godot_v4.6.2-stable_win64_console.exe
```

The supervised runner checks source identity and prevents concurrent Godot runs in this checkout. Keep source files unchanged during capture. Raw PNGs go to a unique temporary directory; only the MP4, GIF and chapter manifest are published under `docs/media/`. A failed capture cannot publish through this script. To encode an already completed capture, pass `-Frames C:/path/to/frame-directory`.

The README follows the concise, product-first organization of [my_ai_town](https://github.com/mewamew/my_ai_town), while documenting this repository's own runtime, controls and limitations.
