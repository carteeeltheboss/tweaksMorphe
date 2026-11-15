# Installs the toolchain Piko needs, entirely inside the user profile (no UAC / admin prompts).
#   * Eclipse Temurin JDK 21   -> %USERPROFILE%\dev-tools\jdk-21
#   * Android SDK cmdline-tools + platform-tools + android-36 + build-tools -> %USERPROFILE%\Android\Sdk
# Idempotent: safe to re-run. Persists ANDROID_HOME and PIKO_JAVA_HOME as *user* variables and
# deliberately leaves the system-wide JAVA_HOME (JDK 17) untouched.

[CmdletBinding()]
param(
    [string]$ToolsRoot = (Join-Path $env:USERPROFILE 'dev-tools'),
    [string]$SdkRoot   = (Join-Path $env:USERPROFILE 'Android\Sdk')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }

New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $SdkRoot   | Out-Null

# ---------------------------------------------------------------- JDK 21
$JdkHome = Join-Path $ToolsRoot 'jdk-21'
if (Test-Path (Join-Path $JdkHome 'bin\java.exe')) {
    Write-Step "JDK 21 already installed at $JdkHome"
} else {
    Write-Step 'Downloading Eclipse Temurin JDK 21 (LTS, Windows x64 zip) from api.adoptium.net'
    $zip = Join-Path $env:TEMP 'temurin-jdk21.zip'
    Invoke-WebRequest -Uri 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse' `
                      -OutFile $zip -UseBasicParsing -TimeoutSec 900
    Write-Ok ("downloaded {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

    Write-Step 'Extracting JDK 21'
    $tmp = Join-Path $env:TEMP ("jdk21-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
    if (-not $inner) { throw 'JDK archive did not contain a top-level folder' }
    Move-Item -Path $inner.FullName -Destination $JdkHome
    Remove-Item -Recurse -Force $tmp
    Remove-Item -Force $zip -ErrorAction SilentlyContinue
}

$env:JAVA_HOME = $JdkHome
$env:Path = (Join-Path $JdkHome 'bin') + ';' + $env:Path
Write-Step 'JDK in use'
# cmd /c merges stderr into stdout, so `java -version` output is not seen as an error record.
cmd /c "`"$JdkHome\bin\java.exe`" -version 2>&1" | ForEach-Object { Write-Ok $_ }
if ($LASTEXITCODE -ne 0) { throw "java -version failed with exit code $LASTEXITCODE" }

# ------------------------------------------------- Android SDK cmdline-tools
$CltLatest    = Join-Path $SdkRoot 'cmdline-tools\latest'
$SdkManager   = Join-Path $CltLatest 'bin\sdkmanager.bat'

if (Test-Path $SdkManager) {
    Write-Step "Android SDK cmdline-tools already installed at $CltLatest"
} else {
    $candidates = @(
        'https://dl.google.com/android/repository/commandlinetools-win-13814211_latest.zip',
        'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip',
        'https://dl.google.com/android/repository/commandlinetools-win-12700392_latest.zip',
        'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
    )
    $url = $null
    foreach ($candidate in $candidates) {
        try {
            $resp = Invoke-WebRequest -Uri $candidate -Method Head -UseBasicParsing -TimeoutSec 60
            if ($resp.StatusCode -eq 200) { $url = $candidate; break }
        } catch { Write-Host "    (unavailable: $candidate)" }
    }
    if (-not $url) { throw 'Could not locate a downloadable Android commandline-tools zip at dl.google.com' }

    Write-Step "Downloading Android SDK cmdline-tools from $url"
    $zip = Join-Path $env:TEMP 'android-cmdline-tools.zip'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 900
    Write-Ok ("downloaded {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

    Write-Step 'Extracting cmdline-tools'
    $tmp = Join-Path $env:TEMP ("clt-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $SdkRoot 'cmdline-tools') | Out-Null
    Move-Item -Path (Join-Path $tmp 'cmdline-tools') -Destination $CltLatest
    Remove-Item -Recurse -Force $tmp
    Remove-Item -Force $zip -ErrorAction SilentlyContinue
}

if (-not (Test-Path $SdkManager)) { throw "sdkmanager not found at $SdkManager" }

# ------------------------------------------------------------- SDK packages
Write-Step 'Accepting Android SDK licenses'
$yesFile = Join-Path $env:TEMP 'sdk-yes.txt'
Set-Content -Path $yesFile -Value (("y`r`n" * 80)) -NoNewline -Encoding Ascii
$licLog = Join-Path $env:TEMP 'sdk-licenses.log'
cmd /c "`"$SdkManager`" --licenses --sdk_root=`"$SdkRoot`" < `"$yesFile`" > `"$licLog`" 2>&1"
Write-Ok "licenses accepted (exit $LASTEXITCODE)"

$packages = @('platform-tools', 'platforms;android-36', 'build-tools;36.0.0', 'build-tools;37.0.0')
Write-Step ("Installing SDK packages: " + ($packages -join ', '))
$pkgArgs = ($packages | ForEach-Object { "`"$_`"" }) -join ' '
$pkgLog = Join-Path $env:TEMP 'sdk-packages.log'
cmd /c "`"$SdkManager`" --sdk_root=`"$SdkRoot`" $pkgArgs > `"$pkgLog`" 2>&1"
$pkgExit = $LASTEXITCODE
Get-Content -Path $pkgLog -Tail 8 | ForEach-Object { Write-Ok $_ }
if ($pkgExit -ne 0) { throw "sdkmanager failed with exit code $pkgExit (see $pkgLog)" }
Remove-Item -Force $yesFile -ErrorAction SilentlyContinue

# ------------------------------------------------- persistent user variables
[Environment]::SetEnvironmentVariable('ANDROID_HOME',       $SdkRoot, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT',   $SdkRoot, 'User')
[Environment]::SetEnvironmentVariable('PIKO_JAVA_HOME',     $JdkHome, 'User')
[Environment]::SetEnvironmentVariable('PIKO_ANDROID_HOME',  $SdkRoot, 'User')

$env:ANDROID_HOME     = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot

Write-Step 'Installed SDK layout'
Get-ChildItem -Path $SdkRoot -Directory | ForEach-Object { Write-Ok $_.Name }
Write-Ok ('platforms: ' + ((Get-ChildItem (Join-Path $SdkRoot 'platforms') -Directory -ErrorAction SilentlyContinue).Name -join ', '))
Write-Ok ('build-tools: ' + ((Get-ChildItem (Join-Path $SdkRoot 'build-tools') -Directory -ErrorAction SilentlyContinue).Name -join ', '))

Write-Host ''
Write-Host 'TOOLCHAIN INSTALL COMPLETE' -ForegroundColor Green
Write-Host "  PIKO_JAVA_HOME    = $JdkHome"
Write-Host "  ANDROID_HOME      = $SdkRoot"
exit 0
