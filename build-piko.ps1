<#
.SYNOPSIS
    Builds the Piko patch bundle (.mpp) from the current source tree.

.DESCRIPTION
    Runs the project's own Gradle wrapper task `buildAndroid` - the same command Piko's GitHub
    Actions workflow uses (`./gradlew clean buildAndroid`). It never edits your sources; it only
    deletes previously produced .mpp bundles from patches\build\libs so the file it reports is
    provably the one built from your current code.

    On success it prints the absolute path, size, SHA-256 and the source commit the bundle was
    built from. On any failure it prints the tail of the build log and exits non-zero.

.PARAMETER Clean
    Run `gradlew clean buildAndroid` (full rebuild) instead of `gradlew buildAndroid`.

.PARAMETER Task
    Gradle task(s) to run. Defaults to 'buildAndroid'.

.PARAMETER GradleArgs
    Extra arguments forwarded verbatim to the wrapper, e.g. -GradleArgs '--stacktrace','--info'.

.PARAMETER RepoRoot
    Override repository location. Defaults to $env:PIKO_REPO then <script dir>\piko.

.EXAMPLE
    .\build-piko.ps1
.EXAMPLE
    .\build-piko.ps1 -Clean
.EXAMPLE
    .\build-piko.ps1 -GradleArgs '--stacktrace'

.NOTES
    Exit codes: 0 = bundle built and verified, 1 = build failed, 2 = environment problem,
                3 = build reported success but produced no usable .mpp.
#>
[CmdletBinding()]
param(
    [switch]$Clean,
    [string[]]$Task = @('buildAndroid'),
    [string[]]$GradleArgs = @(),
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'piko-env.ps1')

$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$label  = if ($Clean) { 'clean-build' } else { 'build' }
$LogFile = Join-Path $LogDir ("piko-$label-$stamp.log")

function Write-Head { param([string]$m) Write-Host ''; Write-Host $m -ForegroundColor Cyan }
function Fail { param([string]$m, [int]$code) Write-Host ''; Write-Host "ERROR: $m" -ForegroundColor Red; exit $code }

Write-Host 'Piko build' -ForegroundColor Magenta
try   { $env0 = Initialize-PikoEnv -RepoRoot $RepoRoot }
catch { Fail $_.Exception.Message 2 }

if (-not $env0.JavaHome)   { Fail 'No JDK found. Run install-toolchain.ps1 or set PIKO_JAVA_HOME.' 2 }
if (-not $env0.AndroidSdk) { Fail 'No Android SDK found. Run install-toolchain.ps1 or set ANDROID_HOME.' 2 }
if ($env0.JavaMajor -lt 17) { Fail "JDK $($env0.JavaMajor) is too old; Morphe needs 17 (21+ recommended)." 2 }
if (-not (Test-Path $env0.GradlewPath)) { Fail "Gradle wrapper missing: $($env0.GradlewPath)" 2 }

if (-not ($env0.HasFileCreds -or $env0.HasTokenCreds)) {
    Fail 'No GitHub Packages credentials. Run: gh auth refresh -h github.com -s read:packages' 2
}

Push-Location $env0.RepoRoot
try {
    $commit  = (git rev-parse --short HEAD 2>$null | Out-String).Trim()
    $branch  = (git rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
    Write-Host "Branch/commit: $branch @ $commit"

    # Only buildAndroid produces a bundle; other tasks (e.g. :patches:checkStringResources) must
    # not have the existing .mpp deleted or be judged for not regenerating it.
    $needsBundle = $Task -contains 'buildAndroid'

    if ($needsBundle -and (Test-Path $env0.MppDirectory)) {
        $old = Get-ChildItem -Path $env0.MppDirectory -Filter '*.mpp' -File -ErrorAction SilentlyContinue
        if ($old) {
            Write-Host ("Removing {0} stale .mpp bundle(s)" -f $old.Count)
            $old | Remove-Item -Force
        }
    }

    $tasks = @()
    if ($Clean) { $tasks += 'clean' }
    $tasks += $Task
    $allArgs = $tasks + $GradleArgs

    Write-Head ("Running: .\gradlew.bat " + ($allArgs -join ' '))
    Write-Host "Log: $LogFile"
    $started = Get-Date

    # cmd /c merges stderr into stdout so PowerShell does not treat Gradle's stderr as errors,
    # while Tee-Object still streams the build to the console.
    $argLine = ($allArgs | ForEach-Object { "`"$_`"" }) -join ' '
    cmd /c "`"$($env0.GradlewPath)`" $argLine 2>&1" | Tee-Object -FilePath $LogFile
    $exit = $LASTEXITCODE
    $duration = (Get-Date) - $started

    if ($exit -ne 0) {
        Write-Host ''
        Write-Host '--- last 40 lines of build log ---' -ForegroundColor Yellow
        Get-Content -Path $LogFile -Tail 40 | ForEach-Object { Write-Host $_ }
        Fail "Gradle exited with code $exit after $([int]$duration.TotalSeconds)s. Full log: $LogFile" 1
    }

    Write-Head "Gradle finished with exit code 0 in $([int]$duration.TotalSeconds)s"

    if (-not $needsBundle) {
        Write-Host "Task '$($Task -join ' ')' does not produce a bundle; skipping .mpp verification."
        Write-Host ''
        Write-Host 'BUILD OK' -ForegroundColor Green
        exit 0
    }

    $bundles = @(Get-ChildItem -Path $env0.MppDirectory -Filter '*.mpp' -File -ErrorAction SilentlyContinue)
    if ($bundles.Count -eq 0) {
        Fail "Build succeeded but no .mpp was produced under $($env0.MppDirectory)" 3
    }
    $empty = @($bundles | Where-Object { $_.Length -eq 0 })
    if ($empty.Count -gt 0) {
        Fail "Bundle(s) are zero bytes: $(($empty | ForEach-Object { $_.Name }) -join ', ')" 3
    }

    Write-Host 'Generated patch bundle(s):' -ForegroundColor Green
    foreach ($b in $bundles) {
        $hash = (Get-FileHash -Path $b.FullName -Algorithm SHA256).Hash
        Write-Host ("  {0}" -f $b.FullName) -ForegroundColor Green
        Write-Host ("    size   : {0:N0} bytes ({1:N2} MB)" -f $b.Length, ($b.Length / 1MB))
        Write-Host ("    written: {0}" -f $b.LastWriteTime)
        Write-Host ("    sha256 : {0}" -f $hash)
    }

    # Sanity-check the bundle really is a zip container with patch content inside.
    $primary = $bundles | Sort-Object Length -Descending | Select-Object -First 1
    $sig = [System.IO.File]::ReadAllBytes($primary.FullName)[0..1]
    if (-not ($sig[0] -eq 0x50 -and $sig[1] -eq 0x4B)) {
        Fail "$($primary.Name) is not a valid zip container (.mpp must be a zip)" 3
    }
    Write-Host ("  container: valid zip (PK) header - {0}" -f $primary.Name)
    Write-Host ("  built from: $branch @ $commit")

    Write-Host ''
    Write-Host 'BUILD OK' -ForegroundColor Green
    exit 0
}
finally { Pop-Location }
