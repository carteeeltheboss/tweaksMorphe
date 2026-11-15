<#
.SYNOPSIS
    Full clean rebuild of the Piko patch bundle - the exact command Piko's CI runs.

.DESCRIPTION
    Equivalent to `.\gradlew.bat clean buildAndroid`, which is what the project's GitHub Actions
    workflow (.github/workflows/build_pull_request.yml) executes. Delegates to build-piko.ps1 with
    -Clean so the same verification and reporting apply.

    Use this when a build behaves oddly, after switching branches, or after pulling upstream
    changes. It is slower than build-piko.ps1 because Gradle discards previous outputs.

.PARAMETER GradleArgs
    Extra arguments forwarded verbatim to the wrapper.

.PARAMETER RepoRoot
    Override repository location.

.EXAMPLE
    .\clean-build.ps1
.EXAMPLE
    .\clean-build.ps1 -GradleArgs '--stacktrace'

.NOTES
    Exit codes are inherited from build-piko.ps1: 0 = ok, 1 = build failed,
    2 = environment problem, 3 = no usable .mpp produced.
#>
[CmdletBinding()]
param(
    [string[]]$GradleArgs = @(),
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

$buildScript = Join-Path $PSScriptRoot 'build-piko.ps1'
if (-not (Test-Path $buildScript)) {
    Write-Host "ERROR: cannot find build-piko.ps1 next to this script ($buildScript)" -ForegroundColor Red
    exit 2
}

& $buildScript -Clean -GradleArgs $GradleArgs -RepoRoot $RepoRoot
exit $LASTEXITCODE
