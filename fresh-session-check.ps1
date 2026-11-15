<#
.SYNOPSIS
    Proves the setup still works from a brand-new PowerShell session.

.DESCRIPTION
    A terminal opened before the toolchain was installed does not see PIKO_JAVA_HOME or the new
    ANDROID_HOME, so it can disagree with the terminal you open tomorrow. This script discards the
    inherited environment and rebuilds it from the Machine + User registry scopes - exactly what a
    freshly opened PowerShell gets - then runs verify-env.ps1 -Deep and build-piko.ps1 in it, and
    finally reports the git state (branch, remotes, and whether anything is staged).

    Run this after any change to the toolchain, the environment variables, or the git remotes.

.EXAMPLE
    .\fresh-session-check.ps1

.NOTES
    Exit codes: 0 = both scripts passed in a clean environment, 1 = something failed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$tools = $PSScriptRoot

$machine = [Environment]::GetEnvironmentVariables('Machine')
$user    = [Environment]::GetEnvironmentVariables('User')

foreach ($k in @('JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','PIKO_JAVA_HOME',
                 'PIKO_ANDROID_HOME','GITHUB_TOKEN','GITHUB_ACTOR','PIKO_REPO')) {
    Remove-Item ("Env:" + $k) -ErrorAction SilentlyContinue
}
foreach ($k in $machine.Keys) { Set-Item -Path ("Env:" + $k) -Value $machine[$k] }
foreach ($k in $user.Keys) {
    if ($k -eq 'Path') { continue }   # handled below: fresh sessions concatenate Machine + User
    Set-Item -Path ("Env:" + $k) -Value $user[$k]
}
$env:Path = [string]$machine['Path'] + ';' + [string]$user['Path']

Write-Host '=== environment as a NEW PowerShell session sees it ===' -ForegroundColor Cyan
foreach ($n in @('JAVA_HOME','PIKO_JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT')) {
    $v = [Environment]::GetEnvironmentVariable($n)
    Write-Host ("  {0,-18} = {1}" -f $n, $(if ($v) { $v } else { '<unset>' }))
}
Write-Host ("  GITHUB_TOKEN       = {0}" -f $(if ($env:GITHUB_TOKEN) { '<set, inherited>' } else { '<unset - good, scripts derive it>' }))

Write-Host ''
Write-Host '=== 1/2  verify-env.ps1 -Deep ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'verify-env.ps1') -Deep
$verifyExit = $LASTEXITCODE
Write-Host ("verify-env exit code: {0}" -f $verifyExit)

Write-Host ''
Write-Host '=== 2/2  build-piko.ps1 ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'build-piko.ps1')
$buildExit = $LASTEXITCODE
Write-Host ("build-piko exit code: {0}" -f $buildExit)

Write-Host ''
Write-Host '=== git state ===' -ForegroundColor Cyan
$repo = Join-Path $tools 'piko'
if (Test-Path $repo) {
    Push-Location $repo
    Write-Host ("  branch   : " + (git rev-parse --abbrev-ref HEAD | Out-String).Trim())
    Write-Host ("  commit   : " + (git rev-parse HEAD | Out-String).Trim())
    Write-Host ("  origin   : " + (git remote get-url origin | Out-String).Trim())
    Write-Host ("  upstream : " + (git remote get-url upstream | Out-String).Trim())
    Write-Host ("  pushDflt : " + (git config --get remote.pushDefault | Out-String).Trim())
    $staged = (git diff --cached --name-only | Out-String).Trim()
    $status = (git status --porcelain | Out-String).Trim()
    Write-Host ("  staged   : " + $(if ($staged) { "!! $staged" } else { '<nothing staged>' }))
    Write-Host ("  worktree : " + $(if ($status) { 'MODIFIED -> ' + ($status -replace "`r?`n", ' | ') } else { 'clean' }))
    Pop-Location
} else {
    Write-Host "  repository not found at $repo" -ForegroundColor Red
    $buildExit = 1
}

Write-Host ''
if ($verifyExit -eq 0 -and $buildExit -eq 0) {
    Write-Host 'FRESH-SESSION CHECK: PASS' -ForegroundColor Green
    exit 0
} else {
    Write-Host ("FRESH-SESSION CHECK: FAIL (verify={0} build={1})" -f $verifyExit, $buildExit) -ForegroundColor Red
    exit 1
}
