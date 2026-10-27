# P1-z hosted visual required-policy promotion

## Reviewed evidence and scope

This separate policy change starts from RC-B PR #78 head
`4ba7749436c488112483da25f9e7436d9b1ee909`. Hosted run `37122904593`
(artifact `11274357578`) at that head produced
`VISUAL_CANARY verdict=pass rc=0 png_count=75 runtime_errors=0`
and `VISUAL_NEGATIVE verdict=caught_expected_daynight_fault shot_rc=0 assert_rc=1
a1=1 a2=1 gate=1 runtime_errors=0`. The positive package includes the
existing identical-frame cafe-floor self-test: its injected 2F frame yielded
the expected B-only failure at 0.0000 while companion frames and metadata were
preserved. A separate read-only review inspected representative day/night,
season, grove, harbor, cafe-floor, and player-state frames. These receipts
support the currently declared A06 visual positive suite and two A07 targeted
negative arms on that product tree. This policy supersedes the observation
status recorded in P1-x/P1-y; those documents remain the history of the
earlier canary batches.

The hosted job now sets `LT_VISUAL=require`. It retains the positive verdict
and complete evidence upload before a final policy step checks that the
positive verdict is `pass`, the PNG count is nonzero, the undeclared fatal
marker count is zero, and the day/night negative has its exact expected
failure shape. A `skip`, `candidate_fail`, `not_run`, missing receipt, or
wrong negative failure shape makes the job red. The inline cafe-floor negative
already fails `tools/visual_gate.sh` if it loses that exact B-only shape.
Checkout and artifact-upload failures also remain red.

## Rolling hosted raster policy

`hosted_visual_runtime_policy.json` records complete reviewed runtime profiles:
image, Godot archive and binary, Python/Pillow, six apt packages, and Mesa GLX
identity. Schema v2 currently contains exactly three profiles reviewed from runs
`39399019945`, `39402759057` and `40417538860` (previous refresh `38254349222`; original
promotion `37122904593`). The final checker requires every listed receipt line
exactly once, with the whole receipt matching one complete profile. It does
not combine accepted values from different profiles. If GitHub supplies an
unreviewed image or package combination, CI fails with a
distinct `runtime:` reason. A reviewer must compare a fresh complete
positive/negative artifact and visual sample on the changed runtime before
updating this file. Do not relabel runtime drift as a product regression or
silently widen the accepted versions.

The October 12 runtime refresh reviews [PR #84 run 38254349222](https://github.com/ForTe13X/living-town/actions/runs/38254349222),
branch head `21dba7a4de883b97872e4b816901e45021bc62f3`, actual merge-event
checkout `9ba945b3208ab463e6ffb9be12d46a8344e989d9`. Artifact
`11750791291` has archive SHA-256
`9c718ccd8f7e848de0e41d2ef493f8918d08f046543d5a3d0199a67459cb4cb8`.
All 98 artifact-manifest entries match their recorded hashes. Its positive
receipt passes with 75 PNGs and zero scanned runtime errors; the same-runtime
negative catches precisely A1+A2, with successful capture and zero scanned
runtime errors. The inline identical-floor negative also retains its expected
B-only failure. Representative actual images were independently inspected.

Only the exact runner image (`20261004.327.1`) and Python patch version
(`3.11.17`) changed. Godot archive/binary, Pillow, all six apt package versions
and Mesa identity remain identical. The job's two failures were these runtime
identity mismatches; the image policy accepts the newly reviewed identities
without changing verdict checks or widening a version range. Unit tests still
reject an unreviewed runner, Python or Mesa identity.

This evidence approves that raster runtime only. The run failed overall and
used the earlier game tree; it is not final proof for the subsequent Town3D
click fix. The current PR must pass a fresh full workflow after the policy
refresh and final game/ledger changes.

The hosted receipt's `runtime_errors=0` means no markers from the declared
`SCRIPT ERROR`, signal, segmentation, fatal, or out-of-bounds scan. Import
logs can still contain the optional NobodyWho GDExtension missing-library
message; that noise is outside this visual gate and must be handled under
the separate clean-export gate.

## October 20 runtime refresh

[PR #87 run 39399019945](https://github.com/ForTe13X/living-town/actions/runs/39399019945)
reviews branch head `d7e3a2490b7ea8133d189f9353429211e41203ff` and
actual merge-event checkout `09c92e95c51a82afbfca4e38c35886a58ef16fbf`.
Artifact `12253533932` has archive SHA-256
`0e3460cc065fe728ff9ae3f7a906f82f3ac3c9ffbed69482e19140b557395699`.
All 98 recorded member hashes match (88 positive and 10 negative entries).
The positive receipt is `pass rc=0 png_count=75 runtime_errors=0`; the
same-runtime day/night negative retains precisely A1+A2 with successful
capture and zero scanned runtime errors. The inline identical-floor negative
retains its expected B-only failure at 0.0000. Independent review inspected
representative day/night, winter, grove, cafe-floor and harbor/player PNGs.
The [review receipt](hosted-runtime-review-2026-10-20.json) binds these findings.

Only the exact runner image (`20261018.339.1`) and Xvfb package
(`2:21.1.12-1ubuntu1.9`) changed. The other eleven required runtime identities,
Godot hashes, visual goldens and verdict checks are unchanged. Replaying the
actual checker passes with these two exact refreshed pins; a malformed
negative with `a2=0` still fails. The existing policy unit suite also rejects
unreviewed runtime identities and invalid positive/negative receipts.

This requalifies the hosted raster runtime for the existing 2D game canary.
It does not establish 3D cafe asset quality or replace the separate Blender,
GLB and Godot pilot evidence. This reviewed run failed only its stale runtime
pins; a fresh successful workflow is required after the refresh.

## October 20 overlapping runner qualification

The next [PR #87 run 39402759057](https://github.com/ForTe13X/living-town/actions/runs/39402759057)
used runner image `20261012.334.1` while the preceding reviewed run used
`20261018.339.1`. This is evidence of overlapping hosted image rollout, rather
than a visual product regression: the other twelve required runtime identities
match, including Xvfb `2:21.1.12-1ubuntu1.9`. Replacing one exact runner pin
with the other would reject the already reviewed profile on the next assignment.

The new review binds branch head `43baf8e524f4794447b2398d0b48b57e1ba59be4`,
actual merge-event checkout `b9b495264da1dff762803da56e1eea9b07941041`, and
artifact `12255388370`, archive SHA-256
`cea58c67d02a8dd60f93745e772ceb955d0cb17150172254663d0681c712e97b`.
All 98 recorded artifact hashes match (88 positive and 10 negative). The
positive receipt again passes with 75 PNGs and zero scanned runtime errors;
the day/night negative again catches exactly A1+A2, and the inline floor
negative retains its B-only failure. All 77 positive/negative PNG files are
byte-identical to the prior reviewed artifact. Actual day, night, winter-night
and cafe-floor images were also inspected from the new artifact. The
[profile review receipt](hosted-runtime-profile-review-2026-10-20.json)
records the two source runs, archive identities, hash checks and PNG comparison.

Schema v2 retains both complete, explicitly named thirteen-line profiles, each
with its own run, PR head, event checkout and artifact provenance. The checker
still supports historical schema v1 single-profile policies. There are no
wildcards, version ranges, fallback runtime maps or per-field allowlists.
The same thirteen mandatory identity prefixes must appear in each v2 profile.
Duplicate runtime identities, duplicate profiles or JSON keys, missing review
metadata, unreviewed combinations and malformed positive/negative receipts
remain failures. All fifteen hosted-policy tests pass, including a synthetic
cross-profile mixture that must be rejected. Replaying both complete real
artifacts passes with v2; changing the negative control to `a2=0` still fails.

This qualifies only these two exact hosted raster profiles. It changes no
visual goldens, detector thresholds, runtime packages, workflow failure policy
or branch protection. A fresh successful workflow after this policy change is
still required for the current PR; these earlier red runs are not final CI proof.

## Promotion boundary

This change makes the hosted visual job fail on a declared A06/A07 verdict
failure. GitHub branch protection is separate. The policy cannot by itself
establish release sign-off: the PR must
run and pass after this change, and an independent reviewer must assess its
new evidence. The two negative controls do not prove targeted mutant
coverage for every LT-02–LT-05 detector family. A16 civic-phase projection
evidence is open and is not claimed by this promotion. No golden, ModelPath,
or complement anchor is rebaked, and no branch protection is changed here.

## October 26 exact hosted runner qualification

[PR #90 run 40417538860](https://github.com/ForTe13X/living-town/actions/runs/40417538860) used runner image `20261023.334.3`. Artifact `12697720949`, archive SHA-256 `027f496110fce2b62eb5ff61404db14c5fc50fde138728e5bfca62f7ce5f5e99`, binds branch head `a6c0a752fd979e3c2cf41f0d4fe71c7370f81cc3` and actual merge-event checkout `44b31c068a6ffb56e5430c7a2c5c18c55456bdf9`. The event tree equals the PR head tree. All 88 positive and 10 negative manifest entries match. The positive canary passes with 75 PNGs and zero scanned runtime errors; the same-runtime negative catches exactly A1+A2, while the inline identical-floor negative retains its B-only failure. All 77 PNGs match the hashes in the committed October 20 review, and representative actual frames were independently inspected.

Only the runner image differs from the nearest approved profile. The complete thirteen-line profile retains the exact Godot archive/binary, Python/Pillow, six packages and Mesa identities. The two previous profiles remain intact. The unchanged checker passes the real artifact under the new exact profile and still rejects malformed negative controls, skipped positives, duplicate identities and unreviewed runtime combinations. All fifteen existing policy tests pass against the proposed three-profile policy. No workflow, detector threshold, golden, ModelPath anchor, complement ledger or branch-protection setting is changed. The [review receipt](hosted-runtime-review-2026-10-26.json) records provenance, source anchors and replay results.

This qualifies that exact hosted raster runtime for the archived 2D suite. A fresh successful workflow remains required after adopting the policy update; the earlier red run is not final CI proof or Unreal acceptance.
