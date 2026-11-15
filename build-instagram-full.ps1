[CmdletBinding()]
param([switch]$SkipBuild, [string]$InputApkm, [string]$OutputName = 'instagram-452-full-bd')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'piko-env.ps1')
$bdEnv = Initialize-PikoEnv -Quiet
if (-not $InputApkm) {
    $InputApkm = (Get-ChildItem (Join-Path $PSScriptRoot 'apkFiles') -Filter '*452*.apkm' -File | Select-Object -First 1).FullName
}
if (-not $InputApkm) { throw 'Instagram 452.1.0.53.64 APKM is required.' }
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-piko.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Piko build failed.' }
}
$baseline = Get-Content (Join-Path $PSScriptRoot 'instagram-baseline.json') -Raw | ConvertFrom-Json
$bundle = Get-ChildItem $bdEnv.MppDirectory -Filter '*.mpp' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$jar = Get-ChildItem (Join-Path $PSScriptRoot 'morphe-desktop/build/libs') -Filter '*-all.jar' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bundle -or -not $jar) { throw 'Build the Piko bundle and Morphe CLI first.' }
$output = Join-Path $PSScriptRoot "output/$OutputName.apk"
$report = Join-Path $PSScriptRoot "output/reports/$OutputName.json"
$log = Join-Path $PSScriptRoot "logs/$OutputName.log"
New-Item -ItemType Directory -Force (Split-Path $report), (Split-Path $log) | Out-Null
# Keep all default compatible patches. Never use --exclusive for the combined APK.
$cli = @('-Xmx6g', '-jar', $jar.FullName, 'patch', $InputApkm, '-p', $bundle.FullName,
    '--validate', '--verify-with-sdk', '-o', $output, '-r', $report)
try {
    $ErrorActionPreference = 'Continue'
    & (Join-Path $env:JAVA_HOME 'bin/java.exe') @cli 2>&1 | Tee-Object -FilePath $log
    $patchExit = $LASTEXITCODE
} finally { $ErrorActionPreference = 'Stop' }
if ($patchExit -ne 0) { throw "Patching failed: $log" }
$result = Get-Content $report -Raw | ConvertFrom-Json
$required = @($baseline.requiredOriginalPatches) + @('Saved Posts Batch Downloader', 'Profile Batch Downloader')
$missing = @($required | Where-Object { $_ -notin $result.appliedPatches })
if (-not $result.success -or @($result.failedPatches).Count -or $missing.Count -or
    $result.packageName -ne $baseline.packageName -or $result.packageVersion -ne $baseline.packageVersion) {
    throw "Combined APK validation failed. Missing patches: $($missing -join ', '). See $report"
}
Write-Host "PASS: all $($baseline.requiredOriginalPatches.Count) baseline patches and both batch download patches applied. $output"
