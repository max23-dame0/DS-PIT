param(
    [Parameter(Mandatory=$true)][string]$Predictions,
    [Parameter(Mandatory=$true)][string]$ExpectedWindows,
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [string]$PythonExe = "python",
    [string]$BaselineMethod,
    [string]$ProtocolId,
    [string]$BaselineVariant,
    [string]$BaselineConfigId,
    [string]$StateList,
    [Nullable[double]]$ExpectedHopS,
    [int]$Bootstrap = 10000,
    [int]$Permutations = 10000,
    [int]$Seed = 20260911,
    [switch]$NoFigures
)

$scriptPath = Join-Path $PSScriptRoot "analyze_predictions.py"
$argsList = @("$scriptPath", "--predictions", $Predictions, "--expected-windows", $ExpectedWindows,
    "--output-dir", $OutputDir, "--bootstrap", "$Bootstrap", "--permutations", "$Permutations", "--seed", "$Seed")
if ($BaselineMethod) { $argsList += @("--baseline-method", $BaselineMethod) }
if ($ProtocolId) { $argsList += @("--protocol-id", $ProtocolId) }
if ($StateList) { $argsList += @("--state-list", $StateList) }
if ($null -ne $ExpectedHopS) { $argsList += @("--expected-hop-s", "$ExpectedHopS") }
if ($NoFigures) { $argsList += "--no-figures" }
if ($BaselineVariant) { $argsList += @("--baseline-variant", $BaselineVariant) }
if ($BaselineConfigId) { $argsList += @("--baseline-config-id", $BaselineConfigId) }
& $PythonExe @argsList
exit $LASTEXITCODE
