# 228 · P4d Mayoral Platforms and Cross-Phase Roadmap

> This slice returns from the narrow investment-dropout investigation to the main P4–P6 product arc.
> The goal is structural: an election must change how the town is governed before P5 adds banking and
> ownership, and before P6 adds local specialties and trade identity.

## Delivered P4 vertical slice

Mayoral elections now produce an actual governing mandate instead of only a winner and a retrospective
scorecard. `elections.json` defines three bounded platforms:

| Platform | Personality tendency | Town reserve floor | External tax rate |
|---|---|---:|---:|
| Public Care | warm, caring, curious, romantic, bold | 45 | 8% |
| Balanced Books | pragmatic, reserved, rigorous, meticulous, suspicious | 35 | 12% |
| Steady Course | fallback | 40 | 10% |

The winner's platform is selected from authored traits, copied into the term record, and frozen for the
whole term. The existing nightly fiscal loop reads only the platform's reserve floor and tax rate. Existing
structural limits—maximum subsidy, tax slack, conservation, and non-negative balances—remain authoritative.
This is policy variation inside the established fiscal safety envelope, not a second economy.

The civic notice board now shows the active platform, tax rate, and reserve floor beside the mayor, term,
attendance, treasury result, ballot box, and reelection receipt. The governance invariant authenticates the
platform against the elected mayor and requires the public election event, term history, and active state to
agree. A forged or stale platform therefore fails the same hard governance contract as a forged mayor.

## Impact receipt

- Focused governance contract: PASS, including deterministic replay, consecutive terms, platform authority,
  fiscal-policy projection, public-board projection, and the existing performance-vote loop.
- S0, N=12, seeds 1–12, 60 days: all hard invariants 12/12; supply #40 12/12; deterministic replay 3/3.
- N=16, seeds 1–12, 60 days: all hard invariants 12/12; supply #40 11/12, meeting the established soft gate.
- Held-out N=12, seeds 13–30, 60 days: all hard and soft invariants 18/18, including supply and governance.
- The intentional policy effect moved the committed trajectory in seeds 11 and 12 after the first election;
  the other ten committed seed anchors remained unchanged.
- Scenario determinism: 16/16 tracks pass. These 20-day scenarios end before the first mayoral election but
  still authenticate the updated data fingerprint.
- Model path: 4/4 seeds pass with zero failures; its eight-day world trajectory remains before the election.
- The expected missing NobodyWho native-library warning remains non-blocking in headless tests.

## Whole-phase progress

| Phase | Current product state | Remaining coherent work |
|---|---|---|
| P0 Ledger | Operational | Extend categories only when a new money flow lands. |
| P1 Household | Operational | No immediate expansion needed. |
| P2 Import transition | Operational | Add new raw-material lanes when P6 recipes require them. |
| P3 Services | Operational | More venues are content expansion, not a prerequisite. |
| P4 Governance | Core loop operational | Council/approval, one visible civic project, and broader mayoral duties remain. |
| P5 Bank, property, commerce | Bank vertical slice operational | Full-reserve deposits, bounded startup loans, PixelLab counter and finance card landed in P5a; deeds/leases, employer payroll and dividends remain. |
| P6 Local specialties | Foundations only | Local crops/flowers/shellfish, recipes and shops, specialty export, hydrangea festival. |
| P7 Scale foundation | Partially de-risked | Full N=40 grid, 24→40 named employed residents, more interiors. |
| P8 Railway and outsiders | Planned | Requires useful services, banking/ownership, and scale work. |
| P9 Culture and entertainment | Planned | Best after visitors and owners create an audience. |

## Next candidates, ranked by coherence

1. **P5a full-reserve town bank vertical slice — delivered in [229](229-p5a-cooperative-bank-and-impact-receipt.md).**
   Bank cash is conserved, deposits are fully reserved, startup loans are bounded, and the PixelLab teller desk
   opens a transactional finance card in the indoor market.
2. **P4e civic project with council approval.** Give the policy loop one visible town outcome, such as funding
   a hydrangea market square or seawall improvement, with a council vote and a bounded budget. This would
   complete P4's promise before moving fully into P5.
3. **P6a hydrangea and coastal-specialty identity pack.** Use PixelLab for flower beds, market crates, oyster
   baskets, signs, and menu props; connect one specialty recipe and one seasonal festival. This is the highest
   visual-payoff detour and can proceed beside P5 if its simulation changes remain separate.
4. **P7 honest scale grid.** Run the complete N=40 matrix and then fill named jobs/interiors. Do this before
   visitor and railway work, not as a reaction to one historical seed.

With P5a delivered, the recommended route becomes **P4e next, with P6a as the PixelLab visual lane**. Public
and private finance are now distinct, so a council-approved visible town project can make that distinction
legible while the specialty pack supplies the town's next large visual-identity gain.
