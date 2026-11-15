<#
.SYNOPSIS
    Runs the Morphe Desktop CLI against your locally built Piko bundle.

.DESCRIPTION
    Pass-through wrapper: everything you type after the script name is forwarded verbatim to the
    Morphe CLI. It only adds value in three ways - it finds the CLI jar, it selects a JDK new enough
    to run it (the jar is compiled for Java 21 and fails on 17), and it injects
    `--patches <newest local .mpp>` when you did not supply one yourself.

    With no arguments it runs `list-patches`, which is the fastest proof that Morphe can actually
    read what Piko produced.

    Use the CLI's own `--out=<file>` option to write output to a file.

.PARAMETER MorpheArgs
    Forwarded verbatim to the Morphe CLI.

.EXAMPLE
    .\morphe.ps1                                   # list patches from the newest local bundle
.EXAMPLE
    .\morphe.ps1 list-versions                     # supported app versions
.EXAMPLE
    .\morphe.ps1 list-patches -p -v -f com.twitter.android
.EXAMPLE
    .\morphe.ps1 list-patches --out=logs\patches.txt
.EXAMPLE
    .\morphe.ps1 patch --out patched.apk C:\apks\x.apkm
.EXAMPLE
    .\morphe.ps1 --help                            # full CLI usage

.NOTES
    Exit codes: whatever the Morphe CLI returns; 2 = jar, JDK or bundle not found.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MorpheArgs
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'piko-env.ps1')

# --- JDK -----------------------------------------------------------------------
# morphe-desktop ships Java 21 bytecode; running it on 17 dies with
# UnsupportedClassVersionError. Get-PikoJavaHome prefers a 21+ JDK on this machine.
$javaHome = Get-PikoJavaHome -MinimumMajor 21
$javaMajor = Get-PikoJavaVersion -JavaHome $javaHome
if (-not $javaHome) {
    Write-Host 'ERROR: no JDK found. Run .\install-toolchain.ps1 or set PIKO_JAVA_HOME.' -ForegroundColor Red
    exit 2
}
if ($javaMajor -lt 21) {
    Write-Host "ERROR: the Morphe CLI needs Java 21+; best JDK found is $javaMajor at $javaHome" -ForegroundColor Red
    exit 2
}
$java = Join-Path $javaHome 'bin\java.exe'

# --- Morphe CLI jar ------------------------------------------------------------
$desktopLibs = Join-Path $PSScriptRoot 'morphe-desktop\build\libs'
$jar = $null
if (Test-Path $desktopLibs) {
    $jar = @(Get-ChildItem -Path $desktopLibs -Filter '*-all.jar' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0]
}
if (-not $jar) {
    Write-Host 'ERROR: Morphe CLI jar not found. Run .\build-morphe-cli.ps1 first.' -ForegroundColor Red
    exit 2
}

# --- arguments -----------------------------------------------------------------
$cli = @()
if ($MorpheArgs.Count -eq 0) { $cli += 'list-patches' } else { $cli += $MorpheArgs }

# Inject the newest local bundle unless the caller already pointed at one
# (a path or a GitHub repo URL are both accepted by the CLI).
if (($cli -join ' ') -notmatch '(^|\s)--patches') {
    $env0 = Initialize-PikoEnv -Quiet
    $bundle = $null
    if (Test-Path $env0.MppDirectory) {
        $bundle = @(Get-ChildItem -Path $env0.MppDirectory -Filter '*.mpp' -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0]
    }
    if (-not $bundle) {
        Write-Host "ERROR: no .mpp bundle found under $($env0.MppDirectory). Run .\build-piko.ps1 first," -ForegroundColor Red
        Write-Host '       or pass --patches explicitly.' -ForegroundColor Red
        exit 2
    }
    $cli += @('--patches', $bundle.FullName)
    Write-Host "bundle: $($bundle.Name) ($([math]::Round($bundle.Length/1MB,2)) MB)" -ForegroundColor DarkGray
}

Write-Host "jar   : $($jar.Name)   java: $javaMajor" -ForegroundColor DarkGray
Write-Host ("morphe: " + ($cli -join ' ')) -ForegroundColor DarkGray
Write-Host ''

# --- run -----------------------------------------------------------------------
& $java '-jar' $jar.FullName @cli 2>&1 | ForEach-Object { Write-Host $_.ToString() }
$exit = $LASTEXITCODE

if ($exit -ne 0) {
    Write-Host ''
    Write-Host "ERROR: Morphe CLI exited with code $exit" -ForegroundColor Red
}
exit $exit
