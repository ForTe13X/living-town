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

`hosted_visual_runtime_policy.json` records the image, Godot archive and
binary, Python/Pillow, six apt packages, and Mesa GLX identity from reviewed
run `37122904593`. The final checker requires every listed receipt line
exactly once. If GitHub updates the image or a package, CI fails with a
distinct `runtime:` reason. A reviewer must compare a fresh complete
positive/negative artifact and visual sample on the changed runtime before
updating this file. Do not relabel runtime drift as a product regression or
silently widen the accepted versions.

The hosted receipt's `runtime_errors=0` means no markers from the declared
`SCRIPT ERROR`, signal, segmentation, fatal, or out-of-bounds scan. Import
logs can still contain the optional NobodyWho GDExtension missing-library
message; that noise is outside this visual gate and must be handled under
the separate clean-export gate.

## Promotion boundary

This change makes the hosted visual job fail on a declared A06/A07 verdict
failure. GitHub branch protection is separate. The policy cannot by itself
establish release sign-off: the PR must
run and pass after this change, and an independent reviewer must assess its
new evidence. The two negative controls do not prove targeted mutant
coverage for every LT-02–LT-05 detector family. A16 civic-phase projection
evidence is open and is not claimed by this promotion. No golden, ModelPath,
or complement anchor is rebaked, and no branch protection is changed here.
