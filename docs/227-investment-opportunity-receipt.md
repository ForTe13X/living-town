# 227 · Investment Opportunity Receipt

> Follow-up to [226](226-p4c7-impact-and-causal-monitor.md). This receipt tests the next planned question:
> did the trust-to-investment signal become sparse because the pair cannot meet, because trust closes the gate,
> because no investment candidate exists, or because another candidate wins selection?

## Scope

The receipt observes the control trajectory for the same fixed pair used by S5: `aria → ben`, seeds 1–8,
40 simulated days. It records a read-only funnel before each simulation tick:

1. same plane and area;
2. actor ready for a social decision;
3. target available;
4. trust at or above `INVEST_TRUST`;
5. an eligible `give` or `invite` candidate;
6. selected and accepted event;
7. every investment the actor selected with any target.

It does not call `agent_candidates`, `_social_candidates`, or `_rel`. The observer therefore cannot create a
relationship, consume randomness, reorder candidates, or alter the trajectory being measured.

Reproduction:

```powershell
godot --headless --path game --script res://bench/CausalHarness.gd -- `
  --seeds 1-8 --days 40 --receipt-only
```

## Receipt

| Seed | Pair candidate windows | Aria→Ben selected / accepted | Aria investments with any target | Chosen targets |
|---:|---:|---:|---:|---|
| 1 | 14 | 0 / 0 | 3 / 3 | qin×2, fei×1 |
| 2 | 7 | 0 / 0 | 3 / 3 | qin×2, fei×1 |
| 3 | 9 | 0 / 0 | 3 / 3 | hai×1, mei×1, shu×1 |
| 4 | 18 | 1 / 1 | 3 / 3 | ben×1, coco×2 |
| 5 | 11 | 0 / 0 | 3 / 3 | coco×1, qin×2 |
| 6 | 12 | 0 / 0 | 3 / 3 | qin×1, mei×1, evy×1 |
| 7 | 7 | 1 / 1 | 3 / 3 | ben×1, evy×2 |
| 8 | 7 | 0 / 0 | 3 / 3 | evy×1, yong×1, mei×1 |

Aggregate facts:

- pair visible and socially available: **8/8 seeds**;
- trust open and an investment candidate present: **8/8 seeds**;
- fixed pair selected: **2/8 seeds**, 2/2 accepted;
- actor invested with someone: **8/8 seeds**, exactly 24/24 accepted events;
- event mix: **24 give, 0 invite**;
- Ben received 2/24 gifts; the other 22 were routed among eight other residents.

The control metrics and causal result remain unchanged with the receipt enabled: PI `0.260`, cascade `12.875`,
Gini `0.124`; trust low blocks both supported fixed-pair investments (`PN=1.00`, 2/2), and the trust-only S5 gate passes.

The exact all-agent competitive denominator comes from Sim's existing read-only `decision_sink`, after candidate
construction and with the actual chosen index:

| Action | Competitive candidate instances | Chosen | Committed events | Accepted | Directed pairs with a candidate |
|---|---:|---:|---:|---:|---:|
| give | 1,626 | 424 | 336 | 336 | 171 / 182 |
| invite | 21,103 | 124 | 109 | 109 | 182 / 182 |

Candidate-to-choice conversion is therefore about **26.1% for give** and **0.59% for invite**. Invitations are not
missing from the world: every directed resident pair exposes at least one invite candidate. They are usually beaten
by another candidate in the utility comparison.

There is a second, narrower anomaly after selection: 88 chosen give intents and 15 chosen invite intents do not
become committed events before the 40-day run ends. Every event that does commit is accepted, so refusal is not the
loss point. The existing social lifecycle can invalidate a chosen intent between `_apply_social` and
`_commit_social` when the partner is no longer reachable; a dedicated lifecycle trace is required before assigning
all 103 dropouts to that path.

## Analysis

The sparse `aria → ben` binary outcome is not an exposure failure. The pair shares space, clears the social and
trust gates, and has a legal investment candidate in every seed. It is also not a town-wide investment collapse:
Aria spends all three gifts in every seed and every gift is accepted.

The loss happens at **selection and recipient allocation**. Other partners win the utility comparison before Ben in
six seeds. The older 5/8 fixed-pair result and the current 2/8 result therefore cannot be interpreted as a 60% drop
in social warmth. They are different allocations of the same three-gift budget.

The fixed-actor portion also exposes a narrower modeling issue: the current S5 outcome is named “investment” but
Aria's 24 events in this grid are all gifts—no invitations. Town-wide invitation activity exists, but the binary
Aria→Ben outcome remains a gift-allocation statistic rather than a broad measure of vulnerable social investment.

## Decision

No simulation tuning is justified by this result. In particular, this slice does **not** lower `INVEST_TRUST`, add
gifts, force meetings, or boost Ben. Those changes would respond to a pair-allocation statistic as if it measured
system-wide activity.

The lifecycle trace remains a valid diagnostic, but it is deferred. The user explicitly redirected development
away from a microscopic social corner and back to the P4–P6 product arc. No retry, partner-lock, or scoring
change is justified without that trace; meanwhile [228](228-p4d-mayoral-platforms-and-roadmap.md) advances the
larger political-economic loop.

## Delivered monitor changes

- `--receipt` enables the English opportunity receipt.
- Each seed reports stage windows/ticks, pair selection/acceptance, action mix, and chosen-target routes.
- The existing read-only `decision_sink` supplies exact all-agent candidate and chosen counts without rebuilding
  candidate logic in the benchmark.
- The receipt emits an English diagnosis when exposure, eligibility, and actor-wide activity are present but the
  fixed pair remains sparse.
- `--only trust` keeps this investigation to three trajectories per seed instead of running unrelated hypotheses.
- `--receipt-only` runs only the control trajectories and prints the English receipt without paying for any
  counterfactual arms.
