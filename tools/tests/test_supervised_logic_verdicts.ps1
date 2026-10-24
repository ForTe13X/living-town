<# Pure terminal-verdict checks. No Godot, Git, file fixtures or process control. #>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runner = Join-Path $root 'tools/run-godot-supervised.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if (@($errors).Count -gt 0) { throw ($errors.Message -join '; ') }
$functions = @($ast.FindAll({ param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-GodotLogicFailure'
}, $true))
if ($functions.Count -ne 1) { throw 'Expected the exact runner verdict predicate.' }
. ([scriptblock]::Create($functions[0].Extent.Text))
$source = [IO.File]::ReadAllText($runner)
if ($source -notmatch '\$logicFailure = \[bool\]\(Test-GodotLogicFailure \$combined\)') {
  throw 'Runner must apply the tested predicate to combined Godot/stdout/stderr logs.'
}
$cases = @(
  @('existing test failure', 'save_load_test: FAIL (1 fail)', $true),
  @('existing gate failure', '=== S0 GATE: FAIL', $true),
  @('existing test pass', 'save_load_test: PASS (0 fail)', $false),
  @('space single failure', 'space_test: 1 fail', $true),
  @('space multiple failures', 'space_test: 12 fail', $true),
  @('space leading zero nonzero', 'space_test: 001 fail', $true),
  @('space zero', 'space_test: 0 fail', $false),
  @('space all zero digits', 'space_test: 000 fail', $false),
  @('space multiline CRLF', "start`r`n  space_test: 2 fail`r`nend", $true),
  @('space quoted example', 'example space_test: 1 fail', $false),
  @('space diagnostic suffix', 'space_test: 1 fail expected in fixture', $false),
  @('cafe single failure', 'CAFE_GUEST_ACCESS_TEST_FAILS=1', $true),
  @('cafe multiple failures', 'CAFE_GUEST_ACCESS_TEST_FAILS=23', $true),
  @('cafe leading zero nonzero', 'CAFE_GUEST_ACCESS_TEST_FAILS=010', $true),
  @('cafe zero', 'CAFE_GUEST_ACCESS_TEST_FAILS=0', $false),
  @('cafe all zero digits', 'CAFE_GUEST_ACCESS_TEST_FAILS=000', $false),
  @('cafe multiline LF', "start`nCAFE_GUEST_ACCESS_TEST_FAILS=2`nend", $true),
  @('cafe quoted example', 'example CAFE_GUEST_ACCESS_TEST_FAILS=1', $false),
  @('journey failure', '=== PLAYER JOURNEY: FAIL (1 failures) ===', $true),
  @('journey multiple failures', '=== PLAYER JOURNEY: FAIL (12 failures) ===', $true),
  @('journey pass', '=== PLAYER JOURNEY: PASS (0 failures) ===', $false),
  @('journey multiline CRLF', "start`r`n=== PLAYER JOURNEY: FAIL (1 failures) ===`r`nend", $true),
  @('journey quoted example', 'example === PLAYER JOURNEY: FAIL (1 failures) ===', $false),
  @('ordinary negative fixture assertion', '  OK   invalid input FAIL verdict was refused', $false),
  @('empty log', '', $false),
  @('all three passing summaries', "space_test: 0 fail`nCAFE_GUEST_ACCESS_TEST_FAILS=0`n=== PLAYER JOURNEY: PASS (0 failures) ===", $false)
)
foreach ($case in $cases) {
  $actual = Test-GodotLogicFailure ([string]$case[1])
  if ($actual -ne [bool]$case[2]) { throw ('FAIL ' + $case[0] + ': ' + $case[1]) }
  Write-Output ('PASS ' + $case[0])
}
Write-Output ('SUPERVISED_LOGIC_VERDICT_TESTS=PASS cases=' + $cases.Count)
