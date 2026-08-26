[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedHead,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedGameTree,

    [ValidateSet("prepared_not_authorized", "ready_to_finalize")]
    [string]$ExpectedDecision = "prepared_not_authorized",

    [string]$ExpectedBranch = "codex/p1a-takeover",
    [string]$ExpectedUpstream = "origin/codex/p1a-takeover",
    [string]$EvidencePath = (Join-Path $PSScriptRoot "readiness-evidence.json"),
    [switch]$RequireUpstream,
    [switch]$RefreshHostedIdentity,
    [string]$ExternalReviewRef = "",
    [string]$ExternalReviewReportPath = "",
    [string]$ExternalReviewReportSha256 = "",
    [switch]$RequireExternalReviewBinding,
    [switch]$AllowDetachedQa,
    [string]$ExpectedAuthorizationHead = "",
    [string]$ExpectedAuthorizationGameTree = "",
    [string]$ExpectedAuthorizedTransitionHead = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Exact {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Actual,
        [AllowEmptyString()][string]$Expected
    )
    if ($Actual -cne $Expected) {
        throw "$Name mismatch: actual=$Actual expected=$Expected"
    }
}

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Int {
    param([string]$Name, [object]$Actual, [int64]$Expected)
    if ([int64]$Actual -ne $Expected) {
        throw "$Name mismatch: actual=$Actual expected=$Expected"
    }
}

function Git-Text {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $text = (& git @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $text"
    }
    return $text
}

function Git-CapturedText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "git"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $stderr"
    }
    return $stdout
}

function Git-BlobSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateHead,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    Assert-True (-not [System.IO.Path]::IsPathRooted($RelativePath)) "anchor path must be repository-relative: $RelativePath"
    $normalized = $RelativePath.Replace("\\", "/")
    Assert-True (-not $normalized.Contains("..")) "anchor path may not escape candidate tree: $RelativePath"
    $blob = Git-Text @("rev-parse", "--verify", "$CandidateHead`:$normalized")
    Assert-Exact "anchor object type $RelativePath" (Git-Text @("cat-file", "-t", $blob)) "blob"

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "git"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($arg in @("cat-file", "blob", $blob)) { [void]$psi.ArgumentList.Add($arg) }
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $bytes = [System.IO.MemoryStream]::new()
    $proc.StandardOutput.BaseStream.CopyTo($bytes)
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        throw "git cat-file blob $blob failed: $stderr"
    }
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes.ToArray())).ToLowerInvariant()
}

function Assert-ExactPathSet {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$To,
        [Parameter(Mandatory = $true)][string[]]$Expected
    )
    $actual = @((& git diff --name-only $From $To 2>&1 | Out-String).Trim().Split("`n", [System.StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() } | Sort-Object -Unique)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --name-only $From $To failed"
    }
    $want = @($Expected | Sort-Object -Unique)
    Assert-Exact "$Name paths" ($actual -join "|") ($want -join "|")
}

function Resolve-ExternalReview {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$CandidateHead,
        [Parameter(Mandatory = $true)][string]$AuthorizationHead,
        [Parameter(Mandatory = $true)][string]$AuthorizationGameTree,
        [Parameter(Mandatory = $true)][string]$Decision
    )
    $supplied = @(@($ExternalReviewRef, $ExternalReviewReportPath, $ExternalReviewReportSha256) | Where-Object { $_ -ne "" })
    if ($RequireExternalReviewBinding -or $supplied.Count -gt 0) {
        Assert-True ($supplied.Count -eq 3) "external review binding requires ref, report path and report sha256"
        Assert-Exact "external review ref identity" $ExternalReviewRef "origin/codex/main-repo-review"
        $originUrl = (Git-Text @("remote", "get-url", "origin")).TrimEnd("/").ToLowerInvariant()
        Assert-True ($originUrl -eq "https://github.com/forte13x/living-town.git") `
            "canonical origin repository identity is not trusted: $originUrl"
        Assert-True (-not [System.IO.Path]::IsPathRooted($ExternalReviewReportPath)) `
            "external review report path must be a repository-relative Git path"
        $normalizedReportPath = $ExternalReviewReportPath.Replace("\\", "/")
        Assert-True ($normalizedReportPath.StartsWith("analysis/main-repo-review/external-reviews/", [System.StringComparison]::Ordinal)) `
            "external review report path is outside the trusted review directory"
        Assert-True (-not $normalizedReportPath.Contains("..")) `
            "external review report path may not escape the external Git tree"
        Assert-True ($ExternalReviewRef -cne $ExpectedBranch -and $ExternalReviewRef -cne $ExpectedUpstream) `
            "external review ref must not be the candidate branch or its upstream"
        $reviewCommit = Git-Text @("rev-parse", "--verify", "$ExternalReviewRef`^{commit}")
        Assert-True ($reviewCommit -cne $CandidateHead) `
            "external review ref resolves to the candidate head; same-ref provenance is rejected"
        $blobSpec = "$ExternalReviewRef`:$ExternalReviewReportPath"
        $blobSha = Git-Text @("rev-parse", "--verify", $blobSpec)
        $raw = Git-CapturedText @("show", "--format=", $blobSpec)
        $actualSha = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($raw))).ToLowerInvariant()
        Assert-Exact "external review content sha256" $actualSha $ExternalReviewReportSha256.ToLowerInvariant()
        try { $report = $raw | ConvertFrom-Json } catch { throw "external review report is not valid JSON: $blobSpec" }
        Assert-Exact "external review ref" ([string]$report.review_ref) $ExternalReviewRef
        Assert-Exact "external review contract" ([string]$report.contract) "living-town-independent-review-report-v1"
        Assert-Exact "external review role" ([string]$report.review_role) "independent_qa_refute"
        Assert-Exact "external review status" ([string]$report.status) "completed"
        Assert-Exact "external review product head" ([string]$report.product_head) $AuthorizationHead
        Assert-Exact "external review game tree" ([string]$report.game_tree) $AuthorizationGameTree
        $authorizationTree = Git-Text @("show", "-s", "--format=%T", $AuthorizationHead)
        Assert-Exact "external review root tree" ([string]$report.commit_tree) $authorizationTree
        & git merge-base --is-ancestor $AuthorizationHead $CandidateHead
        Assert-True ($LASTEXITCODE -eq 0) "external authorization target is not an ancestor of candidate"
        $expectedVerdict = if ($Decision -eq "ready_to_finalize") { "APPROVE_ANCHOR_FINALIZE" } else { "REQUEST_CHANGES" }
        Assert-Exact "external review verdict" ([string]$report.verdict) $expectedVerdict
        return [ordered]@{ ref = $ExternalReviewRef; ref_commit = $reviewCommit; path = $ExternalReviewReportPath; blob_sha = $blobSha; sha256 = $actualSha; verdict = [string]$report.verdict; authorization_head = $AuthorizationHead; authorization_game_tree = $AuthorizationGameTree }
    }
    if ($Decision -eq "ready_to_finalize") {
        throw "ready_to_finalize requires an externally supplied review ref/report/hash binding"
    }
    return $null
}

$repo = Git-Text @("rev-parse", "--show-toplevel")
Push-Location $repo
try {
    Assert-True (Test-Path -LiteralPath $EvidencePath) "evidence file missing: $EvidencePath"
    $evidence = Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Exact "evidence contract" ([string]$evidence.contract) "living-town-anchor-finalize-readiness-v1"
    if ($null -ne $evidence.external_review_binding -and [bool]$evidence.external_review_binding.required) {
        $RequireExternalReviewBinding = $true
    }

    $head = Git-Text @("rev-parse", "HEAD")
    $branch = Git-Text @("branch", "--show-current")
    $gameTree = Git-Text @("rev-parse", "HEAD:game")
    $authorizationHead = if ($ExpectedAuthorizationHead -ne "") { $ExpectedAuthorizationHead } else { $ExpectedHead }
    $authorizationGameTree = if ($ExpectedAuthorizationGameTree -ne "") { $ExpectedAuthorizationGameTree } else { $ExpectedGameTree }
    Assert-Exact "HEAD" $head $ExpectedHead
    if ($AllowDetachedQa) {
        Assert-True ($ExpectedDecision -eq "prepared_not_authorized" -or ($ExpectedAuthorizationHead -ne "" -and $ExpectedAuthorizationGameTree -ne "" -and $ExpectedAuthorizedTransitionHead -ne "")) `
            "detached ready QA requires exact authorization target and transition head"
        Assert-Exact "detached branch" $branch ""
        $candidateRef = Git-Text @("rev-parse", "--verify", "$ExpectedUpstream`^{commit}")
        Assert-Exact "detached candidate ref" $candidateRef $ExpectedHead
    } else {
        Assert-Exact "branch" $branch $ExpectedBranch
    }
    Assert-Exact "game tree" $gameTree $ExpectedGameTree
    $externalReview = Resolve-ExternalReview -Repo $repo -CandidateHead $ExpectedHead `
		-AuthorizationHead $authorizationHead -AuthorizationGameTree $authorizationGameTree -Decision $ExpectedDecision

    $dirty = Git-Text @("status", "--porcelain=v1", "--untracked-files=all")
    Assert-Exact "worktree status" $dirty ""
    if ($RequireUpstream) {
        $upstream = Git-Text @("rev-parse", $ExpectedUpstream)
        Assert-Exact "upstream head" $upstream $ExpectedHead
    }

    if ($ExpectedDecision -eq "ready_to_finalize") {
        Assert-True ($ExpectedAuthorizationHead -ne "" -and $ExpectedAuthorizationGameTree -ne "" -and $ExpectedAuthorizedTransitionHead -ne "") `
            "ready_to_finalize requires exact authorization target/head/tree and authorized transition head"
        Assert-Exact "evidence authorization head" ([string]$evidence.frozen.product_head) $authorizationHead
        Assert-Exact "evidence authorization game tree" ([string]$evidence.frozen.game_tree) $authorizationGameTree
        $authorizedPaths = @(
            "tools/gate_complement_ledger.json",
            "game/bench/golden_digests.json",
            "game/bench/modelpath_anchor.json",
            "analysis/p1w/readiness-evidence.json"
        )
        $correctivePaths = @(
            "tools/gate_complement_ledger.json",
            "analysis/p1w/verify-anchor-finalize-readiness.ps1",
            "analysis/p1w/readiness-evidence.json"
        )
        & git merge-base --is-ancestor $authorizationHead $ExpectedAuthorizedTransitionHead
        Assert-True ($LASTEXITCODE -eq 0) "authorization target is not an ancestor of authorized transition"
        & git merge-base --is-ancestor $ExpectedAuthorizedTransitionHead $ExpectedHead
        Assert-True ($LASTEXITCODE -eq 0) "authorized transition is not an ancestor of candidate"
        Assert-ExactPathSet "authorized anchor transition" $authorizationHead $ExpectedAuthorizedTransitionHead $authorizedPaths
        Assert-ExactPathSet "post-authorization corrective transition" $ExpectedAuthorizedTransitionHead $ExpectedHead $correctivePaths
        Assert-Exact "authorized transition game tree" (Git-Text @("rev-parse", "$($ExpectedAuthorizedTransitionHead):game")) $ExpectedGameTree
    } else {
        Assert-Exact "evidence branch" ([string]$evidence.frozen.branch) $ExpectedBranch
        if (-not $AllowDetachedQa) {
            Assert-Exact "evidence game tree" ([string]$evidence.frozen.game_tree) $ExpectedGameTree
        }
        & git merge-base --is-ancestor ([string]$evidence.frozen.product_head) $ExpectedHead
        Assert-True ($LASTEXITCODE -eq 0) "frozen product head is not an ancestor of expected head"
        $frozenGameTree = Git-Text @("rev-parse", "$($evidence.frozen.product_head):game")
        Assert-Exact "frozen product game tree" $frozenGameTree ([string]$evidence.frozen.game_tree)
    }

    foreach ($anchor in @($evidence.anchors)) {
        $sha = Git-BlobSha256 -CandidateHead $ExpectedHead -RelativePath ([string]$anchor.path)
        Assert-Exact "anchor sha $($anchor.path)" $sha ([string]$anchor.sha256)
        $anchorTree = Git-Text @("rev-parse", "$($anchor.anchor_commit):game")
        Assert-Exact "anchor baked tree $($anchor.path)" $anchorTree ([string]$anchor.baked_game_tree)
        & git merge-base --is-ancestor ([string]$anchor.anchor_commit) $ExpectedHead
        Assert-True ($LASTEXITCODE -eq 0) "anchor commit is not reachable: $($anchor.anchor_commit)"
        if ($ExpectedDecision -eq "ready_to_finalize") {
            Assert-Exact "anchor final game tree $($anchor.path)" $anchorTree $ExpectedGameTree
        } else {
            Assert-True ($anchorTree -cne $ExpectedGameTree) "anchor unexpectedly already matches current game tree"
        }
    }

    $held = $evidence.held_out
    Assert-Exact "held-out outcome" ([string]$held.outcome) "pass"
    Assert-Exact "held-out identity" ([string]$held.source_identity) "exact_commit"
    Assert-True ([bool]$held.source_stable) "held-out source was not stable"
    Assert-True ([bool]$held.cleanup_verified) "held-out cleanup was not verified"
    Assert-Int "held-out seeds" $held.seeds 18
    Assert-Int "held-out days" $held.days 60
    Assert-Int "held-out hard" $held.hard_pass 18
    Assert-Int "held-out #40" $held.soft_40_pass 18
    Assert-Int "held-out #44" $held.trade_44_pass 18
    Assert-Int "held-out #45" $held.trade_45_pass 18
    Assert-Int "held-out #46" $held.trade_46_pass 18
    Assert-Int "held-out det" $held.determinism_pass 1
    Assert-Int "held-out import count" $held.import_count 248
    Assert-Int "held-out import coverage" $held.import_seed_coverage 18
    Assert-Int "held-out export count" $held.export_count 82
    Assert-Int "held-out export coverage" $held.export_seed_coverage 17
    Assert-Int "held-out script errors" $held.script_error_count 0
    Assert-Int "held-out fatal" $held.fatal_count 0

    $n24 = $evidence.total_n24
    Assert-Exact "N24 outcome" ([string]$n24.outcome) "pass"
    Assert-Exact "N24 identity" ([string]$n24.source_identity) "exact_commit"
    Assert-Exact "N24 mode" ([string]$n24.mode) "total"
    Assert-True ([bool]$n24.source_stable) "N24 source was not stable"
    Assert-True ([bool]$n24.cleanup_verified) "N24 cleanup was not verified"
    Assert-Int "N24 requested" $n24.requested 24
    Assert-Int "N24 core" $n24.core 23
    Assert-Int "N24 total" $n24.total 24
    Assert-Int "N24 hard" $n24.hard_pass 12
    Assert-Int "N24 #40" $n24.soft_40_pass 11
    Assert-Int "N24 #44" $n24.trade_44_pass 12
    Assert-Int "N24 #45" $n24.trade_45_pass 12
    Assert-Int "N24 #46" $n24.trade_46_pass 12
    Assert-Int "N24 det" $n24.determinism_pass 1
    Assert-Int "N24 #40 red seed count" @($n24.soft_40_red_seeds).Count 1
    Assert-Int "N24 #40 red seed" $n24.soft_40_red_seeds[0] 6
    Assert-Int "N24 script errors" $n24.script_error_count 0
    Assert-Int "N24 fatal" $n24.fatal_count 0

    $on = $evidence.logistics_on
    Assert-Int "ON exit" $on.exit_code 0
    Assert-Int "ON seeds" $on.seeds 12
    Assert-Int "ON trade invariants" $on.trade_invariants_pass 12
    foreach ($family in @("arrival", "import", "export", "unload")) {
        Assert-Int "ON coverage $family" $on.coverage.$family 12
        Assert-True ([int64]$on.totals.$family -gt 0) "ON $family total is vacuous"
    }
    Assert-Int "ON arrival total" $on.totals.arrival 240
    Assert-Int "ON import total" $on.totals.import 126
    Assert-Int "ON export total" $on.totals.export 84
    Assert-Int "ON unload total" $on.totals.unload 126
    Assert-Int "ON script errors" $on.script_error_count 0
    Assert-Int "ON fatal" $on.fatal_count 0

    $off = $evidence.logistics_off
    Assert-Int "OFF exit" $off.exit_code 0
    Assert-Int "OFF seeds" $off.seeds 3
    Assert-Int "OFF repeats" $off.deterministic_repeats 2
    Assert-Int "OFF trade invariants" $off.trade_invariants_pass 3
    foreach ($family in @("arrival", "import", "export", "unload")) {
        Assert-Int "OFF coverage $family" $off.coverage.$family 0
        Assert-Int "OFF total $family" $off.totals.$family 0
    }
    Assert-Int "OFF script errors" $off.script_error_count 0
    Assert-Int "OFF fatal" $off.fatal_count 0

    $hosted = $evidence.hosted_product_run
    $hostedResolvedTree = Git-Text @("rev-parse", "$($hosted.head):game")
    Assert-Exact "hosted game tree" ([string]$hosted.game_tree) $hostedResolvedTree
    Assert-Exact "hosted status" ([string]$hosted.status) "completed"
    Assert-Exact "hosted conclusion" ([string]$hosted.conclusion) "failure"
    Assert-Int "hosted failure families" $hosted.failure_count 4
    Assert-Int "hosted non-anchor failures" $hosted.non_anchor_failure_count 0
    Assert-Int "hosted family set" @($hosted.failure_families).Count 4
    $expectedFamilies = @(
        "complement_ledger_stale",
        "harness_golden_stale",
        "detgate_golden_stale",
        "modelpath_anchor_stale"
    )
    for ($i = 0; $i -lt $expectedFamilies.Count; $i++) {
        Assert-Exact "hosted failure family[$i]" ([string]$hosted.failure_families[$i]) $expectedFamilies[$i]
    }
    & git merge-base --is-ancestor ([string]$hosted.head) $ExpectedHead
    Assert-True ($LASTEXITCODE -eq 0) "hosted product head is not an ancestor of expected head"

    if ($RefreshHostedIdentity) {
        $identityVerifier = Join-Path $repo "analysis/p1s/verify-exact-tip-delivery.ps1"
        $identityJson = & $identityVerifier `
            -RunId ([int64]$hosted.run_id) `
            -ExpectedHead ([string]$hosted.head) `
            -ExpectedBase ([string]$hosted.base) `
            -ExpectedMerge ([string]$hosted.merge)
        if ($LASTEXITCODE -ne 0) {
            throw "hosted identity verifier failed"
        }
        $identity = $identityJson | ConvertFrom-Json
        Assert-Exact "refreshed hosted game tree" ([string]$identity.game_tree) $ExpectedGameTree
        Assert-Exact "refreshed hosted status" ([string]$identity.run_status) "completed"
        Assert-Exact "refreshed hosted conclusion" ([string]$identity.run_conclusion) "failure"
    }

    $review = $evidence.review_gate
    if ($ExpectedDecision -eq "prepared_not_authorized") {
        Assert-Exact "evidence decision" ([string]$evidence.decision) "prepared_not_authorized"
        Assert-Exact "latest completed review verdict" ([string]$review.latest_completed.verdict) "REQUEST_CHANGES"
        Assert-True (-not [bool]$review.latest_completed.covers_current_game_tree) `
            "stale completed review unexpectedly claims current-tree coverage"
        Assert-Exact "current scheduled review" ([string]$review.current_scheduled.status) "in_progress"
        Assert-True (-not [bool]$review.current_scheduled.completed_verdict) `
            "in-progress review unexpectedly claims a completed verdict"
        Assert-True ($null -eq $review.authorizing_completed) `
            "prepared_not_authorized evidence unexpectedly contains an authorizing review"
    } else {
        Assert-True ($null -ne $review.authorizing_completed) "fresh authorizing review is absent"
        Assert-Exact "evidence decision" ([string]$evidence.decision) "ready_to_finalize"
        $approval = $review.authorizing_completed
        Assert-Exact "authorizing review status" ([string]$approval.status) "completed"
        Assert-Exact "authorizing review verdict" ([string]$approval.verdict) "APPROVE_ANCHOR_FINALIZE"
        $approvalGameTree = if ($ExpectedDecision -eq "ready_to_finalize") { $authorizationGameTree } else { $ExpectedGameTree }
        Assert-Exact "authorizing review game tree" ([string]$approval.game_tree) $approvalGameTree
        & git merge-base --is-ancestor ([string]$approval.product_head) $ExpectedHead
        Assert-True ($LASTEXITCODE -eq 0) "authorizing review head is not an ancestor of expected head"
    }

    [ordered]@{
        contract = "living-town-anchor-finalize-readiness-verdict-v1"
        decision = $ExpectedDecision
        authorized = ($ExpectedDecision -eq "ready_to_finalize")
        head = $ExpectedHead
        game_tree = $ExpectedGameTree
        branch = $ExpectedBranch
        upstream_checked = [bool]($RequireUpstream -or $AllowDetachedQa)
        detached_qa = [bool]$AllowDetachedQa
        hosted_identity_refreshed = [bool]$RefreshHostedIdentity
        protected_anchors_unchanged = $true
        held_out = "18/18 hard; 18/18 #40; 18/18 #44/#45/#46; det 1/1"
        total_n24 = "12/12 hard; 11/12 #40; 12/12 #44/#45/#46; det 1/1"
        logistics_on = "12/12 arrival/import/export/unload coverage"
        logistics_off = "3/3 x two runs: exact zero"
        review_gate = $(if ($ExpectedDecision -eq "ready_to_finalize") { "completed approval" } else { "fresh completed approval absent" })
		external_review = $externalReview
    } | ConvertTo-Json -Depth 5
} finally {
    Pop-Location
}
