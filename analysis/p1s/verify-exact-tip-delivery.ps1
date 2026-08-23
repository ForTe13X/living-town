param(
    [Parameter(Mandatory = $true)]
    [int64]$RunId,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedHead,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedBase,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedMerge,

    [int]$PullRequest = 6,
    [string]$Repository = "ForTe13X/living-town",
    [switch]$RequireLivePr
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Exact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [AllowEmptyString()]
        [string]$Actual,
        [AllowEmptyString()]
        [string]$Expected
    )
    if ($Actual -cne $Expected) {
        throw "$Name mismatch: actual=$Actual expected=$Expected"
    }
}

$run = gh run view $RunId --repo $Repository `
    --json status,conclusion,event,headSha,url,jobs | ConvertFrom-Json
$runSnapshot = gh api "repos/$Repository/actions/runs/$RunId" | ConvertFrom-Json
$merge = gh api "repos/$Repository/git/commits/$ExpectedMerge" | ConvertFrom-Json

Assert-Exact "run head" ([string]$run.headSha) $ExpectedHead
Assert-Exact "run event" ([string]$run.event) "pull_request"
Assert-Exact "run status" ([string]$run.status) "completed"
Assert-Exact "run snapshot head" ([string]$runSnapshot.head_sha) $ExpectedHead
Assert-Exact "run snapshot event" ([string]$runSnapshot.event) "pull_request"
Assert-Exact "run snapshot status" ([string]$runSnapshot.status) "completed"
Assert-Exact "merge SHA" ([string]$merge.sha) $ExpectedMerge

$snapshotPrRows = @($runSnapshot.pull_requests | Where-Object {
    [int]$_.number -eq $PullRequest
})
if ($snapshotPrRows.Count -ne 1) {
    throw "run PR snapshot count mismatch: actual=$($snapshotPrRows.Count) expected=1"
}
$snapshotPr = $snapshotPrRows[0]

$livePr = $null
if ($RequireLivePr) {
    $livePr = gh pr view $PullRequest --repo $Repository `
        --json headRefOid,baseRefOid,isDraft,mergeStateStatus,url | ConvertFrom-Json
    Assert-Exact "live PR head" ([string]$livePr.headRefOid) $ExpectedHead
    Assert-Exact "live PR base" ([string]$livePr.baseRefOid) $ExpectedBase
}

if ($merge.parents.Count -ne 2) {
    throw "merge parent count mismatch: actual=$($merge.parents.Count) expected=2"
}
Assert-Exact "merge parent[0]" ([string]$merge.parents[0].sha) $ExpectedBase
Assert-Exact "merge parent[1]" ([string]$merge.parents[1].sha) $ExpectedHead

$headGame = git rev-parse "${ExpectedHead}:game"
$mergeGame = git rev-parse "${ExpectedMerge}:game"
Assert-Exact "merge game tree" ([string]$mergeGame) ([string]$headGame)

$jobRows = @($run.jobs | ForEach-Object {
    [ordered]@{
        id = [int64]$_.databaseId
        name = [string]$_.name
        status = [string]$_.status
        conclusion = [string]$_.conclusion
        url = [string]$_.url
    }
})
if ($jobRows.Count -eq 0) {
    throw "run has no jobs"
}
if (@($jobRows | Where-Object { $_.status -ne "completed" }).Count -ne 0) {
    throw "run contains non-terminal jobs"
}

[ordered]@{
    schema = 1
    repository = $Repository
    pull_request = $PullRequest
    run_pr_association_url = [string]$snapshotPr.url
    live_pr_checked = [bool]$RequireLivePr
    live_pr_url = $(if ($null -eq $livePr) { "" } else { [string]$livePr.url })
    live_pr_draft = $(if ($null -eq $livePr) { $null } else { [bool]$livePr.isDraft })
    live_pr_merge_state = $(if ($null -eq $livePr) { "" } else { [string]$livePr.mergeStateStatus })
    head_sha = $ExpectedHead
    base_sha = $ExpectedBase
    merge_sha = $ExpectedMerge
    game_tree = [string]$headGame
    run_id = $RunId
    run_url = [string]$run.url
    run_status = [string]$run.status
    run_conclusion = [string]$run.conclusion
    jobs = $jobRows
} | ConvertTo-Json -Depth 6
