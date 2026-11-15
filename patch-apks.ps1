<#
.SYNOPSIS
    Patches every APK/APKM in an input folder with the locally built Piko bundle, into .\output.

.DESCRIPTION
    For each app package found in the input folder this script:
      * parses package / version / versionCode out of the APKMirror-style filename,
      * asks the Morphe CLI which versions the bundle actually supports (list-versions) and flags
        each input as SUPPORTED or UNSUPPORTED before patching,
      * runs `morphe patch` writing the result to output\<name>.apk, a machine-readable JSON report
        to output\reports\<name>.json, and the console log to logs\patch-<name>.log,
      * optionally verifies the patched DEX/APK against the Android SDK (--verify-with-sdk),
      * finally writes output\README.md describing every file it produced, with size, SHA-256,
        source file and patch outcome.

    Nothing is installed on a device unless you pass -Install (needs adb + a connected device).

.PARAMETER InputDir
    Folder holding the original APK/APKM files. Default: <script dir>\apkFiles

.PARAMETER OutputDir
    Where patched files and the report go. Default: <script dir>\output

.PARAMETER Force
    Pass --force to Morphe, skipping the app-version compatibility check. Use only to experiment
    with a version Piko does not declare support for - the result may be broken.

.PARAMETER ContinueOnError
    Keep patching remaining files after one fails.

.PARAMETER Install
    Pass --install to Morphe so the patched APK is pushed to the first connected adb device.

.PARAMETER NoVerify
    Skip --verify-with-sdk (faster; verification can also raise false positives).

.EXAMPLE
    .\patch-apks.ps1
.EXAMPLE
    .\patch-apks.ps1 -Force -ContinueOnError
.EXAMPLE
    .\patch-apks.ps1 -Install

.NOTES
    Exit codes: 0 = every input patched, 1 = at least one failed, 2 = environment problem.
#>
[CmdletBinding()]
param(
    [string]$InputDir,
    [string]$OutputDir,
    [switch]$Force,
    [switch]$ContinueOnError,
    [switch]$Install,
    [switch]$NoVerify
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'piko-env.ps1')

if (-not $InputDir)  { $InputDir  = Join-Path $PSScriptRoot 'apkFiles' }
if (-not $OutputDir) { $OutputDir = Join-Path $PSScriptRoot 'output' }

$env0     = Initialize-PikoEnv -Quiet
$javaHome = Get-PikoJavaHome -MinimumMajor 21
$javaMajor= Get-PikoJavaVersion -JavaHome $javaHome
if (-not $javaHome -or $javaMajor -lt 21) {
    Write-Host "ERROR: the Morphe CLI needs Java 21+ (found: $javaHome / $javaMajor)" -ForegroundColor Red
    exit 2
}
$java = Join-Path $javaHome 'bin\java.exe'

$desktopLibs = Join-Path $PSScriptRoot 'morphe-desktop\build\libs'
$jar = @(Get-ChildItem -Path $desktopLibs -Filter '*-all.jar' -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0]
if (-not $jar) {
    Write-Host 'ERROR: Morphe CLI jar not found. Run .\build-morphe-cli.ps1 first.' -ForegroundColor Red
    exit 2
}

$bundle = @(Get-ChildItem -Path $env0.MppDirectory -Filter '*.mpp' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0]
if (-not $bundle) {
    Write-Host "ERROR: no .mpp bundle under $($env0.MppDirectory). Run .\build-piko.ps1 first." -ForegroundColor Red
    exit 2
}

$sdk = Get-PikoAndroidSdk
$reportDir = Join-Path $OutputDir 'reports'
New-Item -ItemType Directory -Force -Path $OutputDir, $reportDir | Out-Null
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Invoke-Morphe {
    param([string[]]$CliArgs, [string]$LogPath)
    & $java '-Xms1024m' '-Xmx6g' '-jar' $jar.FullName @CliArgs 2>&1 |
        ForEach-Object { $_.ToString() } | Tee-Object -FilePath $LogPath | Out-Host
    $exitCode = $LASTEXITCODE
    return [int]$exitCode
}

Write-Host 'Piko patch run' -ForegroundColor Magenta
Write-Host "  bundle : $($bundle.Name) ($([math]::Round($bundle.Length/1MB,2)) MB)"
Write-Host "  jar    : $($jar.Name)"
Write-Host "  java   : $javaMajor"
Write-Host "  input  : $InputDir"
Write-Host "  output : $OutputDir"

# ---------------------------------------------------------------- inputs
$inputs = @(Get-ChildItem -Path $InputDir -File -Include '*.apk','*.apkm','*.xapk','*.apks' -Recurse -ErrorAction SilentlyContinue)
if ($inputs.Count -eq 0) {
    $inputs = @(Get-ChildItem -Path $InputDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^\.(apk|apkm|xapk|apks)$' })
}
if ($inputs.Count -eq 0) {
    Write-Host "ERROR: no APK/APKM files found in $InputDir" -ForegroundColor Red
    exit 2
}
Write-Host "  found  : $($inputs.Count) package(s)"

# --------------------------------------------- supported versions lookup
Write-Host ''
Write-Host '==> Asking the bundle which app versions it supports' -ForegroundColor Cyan
$supported = @{}
$lvLog = Join-Path $logDir 'morphe-list-versions.txt'
$lvArgs = @('list-versions', '--patches', $bundle.FullName)
$null = Invoke-Morphe -CliArgs $lvArgs -LogPath $lvLog
$currentPkg = $null
Get-Content $lvLog -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_ -match 'Package name:\s*(\S+)') { $currentPkg = $Matches[1] }
    elseif ($currentPkg -and $_ -match '^\s+(\S+)\s*(\[versionCodes:[^\]]*\])?\s*\(\d+ patches?\)') {
        $ver = $Matches[1]
        if (-not $supported.ContainsKey($currentPkg)) { $supported[$currentPkg] = @() }
        $supported[$currentPkg] += $ver
    }
}
foreach ($k in $supported.Keys) { Write-Host "    $k -> $($supported[$k] -join ', ')" }

# ------------------------------------------------------------- patching
$results = @()
$index = 0
foreach ($file in $inputs) {
    $index++
    $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

    $pkg = $null; $ver = $null; $vc = $null
    if ($base -match '^(?<pkg>[\w\.]+)_(?<ver>[\w\.\-]+?)-(?<vc>\d+)_') {
        $pkg = $Matches['pkg']; $ver = $Matches['ver']; $vc = $Matches['vc']
    } elseif ($base -match '^(?<pkg>[\w\.]+)_(?<ver>[\w\.\-]+)') {
        $pkg = $Matches['pkg']; $ver = $Matches['ver']
    } else {
        $pkg = 'unknown'; $ver = 'unknown'
    }

    $isSupported = $supported.ContainsKey($pkg) -and ($supported[$pkg] -contains $ver)
    $tag = if ($isSupported) { 'SUPPORTED' } else { 'UNSUPPORTED' }
    $safeName = ("{0}_{1}" -f $pkg, $ver) -replace '[^A-Za-z0-9._-]', '_'
    $outApk   = Join-Path $OutputDir ("patched_{0}.apk" -f $safeName)
    $outJson  = Join-Path $reportDir ("{0}.json" -f $safeName)
    $outLog   = Join-Path $logDir    ("patch-{0}.log" -f $safeName)

    Write-Host ''
    Write-Host ("==> [{0}/{1}] {2} {3}  [{4}]" -f $index, $inputs.Count, $pkg, $ver, $tag) -ForegroundColor Cyan
    Write-Host "    source : $($file.Name) ($([math]::Round($file.Length/1MB,1)) MB)"
    Write-Host "    output : $outApk"

    # Never let an artifact from an earlier run be mistaken for this run's result.
    Remove-Item -LiteralPath $outApk, $outJson -Force -ErrorAction SilentlyContinue

    if (-not $isSupported -and -not $Force) {
        Write-Host '    result : SKIPPED (version is not supported; use -Force to experiment)' -ForegroundColor Yellow
        $results += [pscustomobject]@{
            Package      = $pkg
            Version      = $ver
            VersionCode  = $vc
            Supported    = $false
            SourceFile   = $file.Name
            SourceMB     = [math]::Round($file.Length / 1MB, 1)
            Status       = 'SKIPPED'
            ExitCode     = $null
            OutputFile   = $null
            OutputMB     = 0
            Sha256       = $null
            ReportJson   = $null
            Log          = $null
            Forced       = $false
        }
        continue
    }

    $cli = @('patch', '--patches', $bundle.FullName, '-o', $outApk, '-r', $outJson)
    if (-not $NoVerify -and $sdk) { $cli += "--verify-with-sdk=$sdk" }
    if ($Force)          { $cli += '--force' }
    if ($ContinueOnError){ $cli += '--continue-on-error' }
    if ($Install)        { $cli += '--install' }
    $cli += $file.FullName

    $exit = Invoke-Morphe -CliArgs $cli -LogPath $outLog

    if ($exit -ne 0) {
        Remove-Item -LiteralPath $outApk, $outJson -Force -ErrorAction SilentlyContinue
    }

    $produced = Test-Path $outApk
    $size = if ($produced) { (Get-Item $outApk).Length } else { 0 }
    $sha  = if ($produced -and $size -gt 0) { (Get-FileHash -Path $outApk -Algorithm SHA256).Hash } else { $null }

    $status = if ($exit -eq 0 -and $produced -and $size -gt 0) { 'PATCHED' } else { 'FAILED' }
    $colour = if ($status -eq 'PATCHED') { 'Green' } else { 'Red' }
    Write-Host ("    result : {0} (morphe exit {1})" -f $status, $exit) -ForegroundColor $colour

    $results += [pscustomobject]@{
        Package      = $pkg
        Version      = $ver
        VersionCode  = $vc
        Supported    = $isSupported
        SourceFile   = $file.Name
        SourceMB     = [math]::Round($file.Length / 1MB, 1)
        Status       = $status
        ExitCode     = $exit
        OutputFile   = $(if ($produced) { (Split-Path $outApk -Leaf) } else { $null })
        OutputMB     = [math]::Round($size / 1MB, 1)
        Sha256       = $sha
        ReportJson   = $(if (Test-Path $outJson) { (Split-Path $outJson -Leaf) } else { $null })
        Log          = (Split-Path $outLog -Leaf)
        Forced       = [bool]$Force
    }

    if ($status -ne 'PATCHED' -and -not $ContinueOnError -and $index -lt $inputs.Count) {
        Write-Host ''
        Write-Host 'Stopping after failure (use -ContinueOnError to keep going).' -ForegroundColor Yellow
        break
    }
}

# ------------------------------------------------------------- report
$readme = Join-Path $OutputDir 'README.md'
$ok  = @($results | Where-Object { $_.Status -eq 'PATCHED' })
$skipped = @($results | Where-Object { $_.Status -eq 'SKIPPED' })
$bad = @($results | Where-Object { $_.Status -eq 'FAILED' })

$lines = @()
$lines += '# Patched output'
$lines += ''
$lines += ("Generated {0} by ``patch-apks.ps1``." -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$lines += ''
Push-Location $env0.RepoRoot
$gitBranch = (git rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
$gitCommit = (git rev-parse --short HEAD 2>$null | Out-String).Trim()
Pop-Location
$bundleSha = (Get-FileHash -Path $bundle.FullName -Algorithm SHA256).Hash

$lines += ("* **Patch bundle:** ``piko\patches\build\libs\{0}`` ({1} MB, sha256 ``{2}``)" -f `
            $bundle.Name, [math]::Round($bundle.Length/1MB,2), $bundleSha)
$lines += ("* **Built from:** piko branch ``{0}`` @ ``{1}``" -f $gitBranch, $gitCommit)
$lines += ("* **Patcher:** ``{0}`` on Java {1}" -f $jar.Name, $javaMajor)
$lines += ("* **Result:** {0} patched, {1} skipped, {2} failed" -f $ok.Count, $skipped.Count, $bad.Count)
$lines += ''
$lines += '## Versions this bundle supports'
$lines += ''
foreach ($k in ($supported.Keys | Sort-Object)) {
    $lines += ("* ``{0}`` -> {1}" -f $k, ($supported[$k] -join ', '))
}
$lines += ''
$lines += '## Files'
$lines += ''
foreach ($r in $results) {
    $lines += ("### {0}" -f $(if ($r.OutputFile) { $r.OutputFile } else { "(no output) " + $r.Package + ' ' + $r.Version }))
    $lines += ''
    $lines += ("| | |")
    $lines += ("|---|---|")
    $lines += ("| App | ``{0}`` |" -f $r.Package)
    $lines += ("| Version | ``{0}`` (versionCode {1}) |" -f $r.Version, $(if ($r.VersionCode) { $r.VersionCode } else { '?' }))
    $lines += ("| Supported by this bundle | {0} |" -f $(if ($r.Supported) { '**yes**' } else { '**no**' }))
    $lines += ("| Source | ``apkFiles\{0}`` ({1} MB) |" -f $r.SourceFile, $r.SourceMB)
    $exitText = if ($null -eq $r.ExitCode) { 'n/a' } else { [string]$r.ExitCode }
    $lines += ("| Outcome | **{0}** (Morphe exit {1}) |" -f $r.Status, $exitText)
    if ($r.OutputFile) {
        $lines += ("| Output size | {0} MB |" -f $r.OutputMB)
        $lines += ("| SHA-256 | ``{0}`` |" -f $r.Sha256)
    }
    if ($r.Forced) { $lines += '| Note | patched with ``--force``, version check skipped - treat as experimental |' }
    $lines += ("| JSON report | ``reports\{0}`` |" -f $(if ($r.ReportJson) { $r.ReportJson } else { 'n/a' }))
    $lines += ("| Full log | ``{0}`` |" -f $(if ($r.Log) { "..\logs\$($r.Log)" } else { 'n/a' }))
    $lines += ''
}
$lines += '## Installing'
$lines += ''
$lines += '```powershell'
$lines += '# with a device connected and USB debugging on:'
$lines += '& "C:\Users\Karim\Android\Sdk\platform-tools\adb.exe" install -r output\patched_<name>.apk'
$lines += '# or let Morphe do it during patching:'
$lines += '.\patch-apks.ps1 -Install'
$lines += '```'
$lines += ''
$lines += 'The patched APK is signed by Morphe with its own key, so it installs alongside - not over -'
$lines += 'a Play Store install of the same app. Uninstall the store version first, or use Piko''s'
$lines += 'Instagram "Clone" patch to change the package name.'
$lines += ''

Set-Content -Path $readme -Value ($lines -join "`r`n") -Encoding utf8

Write-Host ''
Write-Host '================ SUMMARY ================' -ForegroundColor Magenta
$results | Format-Table Package, Version, Supported, Status, ExitCode, OutputMB -AutoSize | Out-String | Write-Host
Write-Host "Report written to $readme"
Write-Host ("Patched: {0}   Skipped: {1}   Failed: {2}" -f $ok.Count, $skipped.Count, $bad.Count) -ForegroundColor $(if ($bad.Count -eq 0) { 'Green' } else { 'Yellow' })

if ($bad.Count -gt 0) { exit 1 } else { exit 0 }
