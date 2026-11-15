<#
.SYNOPSIS
    Builds the Morphe Desktop CLI, which is what actually consumes a Piko .mpp bundle.

.DESCRIPTION
    Piko compiles to a patch bundle, not an APK. To turn a bundle into a patched app you need the
    Morphe Desktop CLI. This script clones it (dev branch, per the Morphe documentation) into
    <script dir>\morphe-desktop if absent, then runs its own Gradle wrapper `build` task and
    reports the resulting runnable jar.

    The jar can then list the patches inside a bundle, or patch a real APK/APKM:

        java -jar morphe-desktop-all.jar list --patches piko\patches\build\libs\patches-3.11.1.mpp
        java -jar morphe-desktop-all.jar patch --patches <bundle>.mpp --out patched.apk input.apkm

.PARAMETER Force
    Re-run the Gradle build even if a jar already exists.

.EXAMPLE
    .\build-morphe-cli.ps1

.NOTES
    Exit codes: 0 = jar built, 1 = build failed, 2 = environment problem.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$CloneRoot
)

$ErrorActionPreference = 'Stop'
# Resolved here rather than as a param default: $PSScriptRoot is not populated yet while
# parameter defaults are being bound.
if (-not $CloneRoot) { $CloneRoot = $PSScriptRoot }
. (Join-Path $PSScriptRoot 'piko-env.ps1')

$desktopDir = Join-Path $CloneRoot 'morphe-desktop'
$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("morphe-cli-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")

$javaHome = Get-PikoJavaHome
if (-not $javaHome) {
    Write-Host 'ERROR: no JDK found. Run install-toolchain.ps1 or set PIKO_JAVA_HOME.' -ForegroundColor Red
    exit 2
}
$env:JAVA_HOME = $javaHome
$env:Path = (Join-Path $javaHome 'bin') + ';' + $env:Path
$sdk = Get-PikoAndroidSdk
if ($sdk) { $env:ANDROID_HOME = $sdk; $env:ANDROID_SDK_ROOT = $sdk }

# Morphe resolves some dependencies from GitHub Packages too.
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    $tok = (& gh auth token 2>$null | Out-String).Trim()
    if ($tok -and $tok.Length -gt 20) {
        $env:GITHUB_TOKEN = $tok
        if (-not $env:GITHUB_ACTOR) { $env:GITHUB_ACTOR = (& gh api user --jq .login 2>$null | Out-String).Trim() }
    }
}

if (-not (Test-Path (Join-Path $desktopDir 'gradlew.bat'))) {
    Write-Host "==> Cloning Morphe Desktop (dev branch) into $desktopDir" -ForegroundColor Cyan
    git clone -b dev https://github.com/MorpheApp/morphe-desktop $desktopDir 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: clone failed ($LASTEXITCODE)" -ForegroundColor Red; exit 2 }
}

function Get-MorpheJar {
    $libs = Join-Path $desktopDir 'build\libs'
    if (-not (Test-Path $libs)) { return $null }
    return @(Get-ChildItem -Path $libs -Filter '*-all.jar' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

$existing = Get-MorpheJar
if ($existing -and -not $Force) {
    Write-Host "==> Morphe CLI jar already built: $($existing.FullName)" -ForegroundColor Green
    exit 0
}

Write-Host '==> Building Morphe Desktop CLI (.\gradlew.bat build)' -ForegroundColor Cyan
Write-Host "    JDK : $javaHome"
Write-Host "    Log : $LogFile"

Push-Location $desktopDir
try {
    cmd /c "`"gradlew.bat`" build --console=plain 2>&1" | Tee-Object -FilePath $LogFile
    $exit = $LASTEXITCODE
}
finally { Pop-Location }

if ($exit -ne 0) {
    Write-Host ''
    Write-Host '--- last 40 lines ---' -ForegroundColor Yellow
    Get-Content -Path $LogFile -Tail 40 | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host "ERROR: Morphe CLI build failed with exit code $exit. Full log: $LogFile" -ForegroundColor Red
    exit 1
}

$jar = Get-MorpheJar
if (-not $jar) {
    Write-Host 'ERROR: build succeeded but no *-all.jar was produced under morphe-desktop\build\libs' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host ("MORPHE CLI OK: {0} ({1:N2} MB)" -f $jar.FullName, ($jar.Length / 1MB)) -ForegroundColor Green
exit 0
