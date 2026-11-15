<#
.SYNOPSIS
    Verifies that this machine can build Piko, without building it.

.DESCRIPTION
    Checks, in order: repository + git configuration, Gradle wrapper, JDK, Android SDK packages
    and licences, GitHub Packages credentials (with a live probe of the Morphe registry), and
    network reachability of the repositories Gradle needs.

    Prints one line per check. Exits 0 when nothing failed, 1 when at least one check failed.

.PARAMETER Deep
    Additionally run `.\gradlew.bat help` to prove Gradle can configure the build and resolve the
    Morphe plugin. Slower (first run downloads the Gradle distribution) but conclusive.

.PARAMETER RepoRoot
    Override repository location. Defaults to $env:PIKO_REPO then <script dir>\piko.

.EXAMPLE
    .\verify-env.ps1
.EXAMPLE
    .\verify-env.ps1 -Deep

.NOTES
    Exit codes: 0 = ready to build, 1 = one or more checks failed.
#>
[CmdletBinding()]
param(
    [switch]$Deep,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'piko-env.ps1')

$script:Failures = 0
$script:Warnings = 0

function Ok    { param([string]$n, [string]$d) Write-Host ("[ OK ]   {0,-26} {1}" -f $n, $d) -ForegroundColor Green }
function Warn  { param([string]$n, [string]$d) Write-Host ("[WARN]   {0,-26} {1}" -f $n, $d) -ForegroundColor Yellow; $script:Warnings++ }
function Bad   { param([string]$n, [string]$d) Write-Host ("[FAIL]   {0,-26} {1}" -f $n, $d) -ForegroundColor Red; $script:Failures++ }
function Head  { param([string]$d) Write-Host ''; Write-Host $d -ForegroundColor Cyan }

Write-Host 'Piko environment verification' -ForegroundColor Magenta
Write-Host ("Run at {0} on {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME)

# ---------------------------------------------------------------- repository
Head 'Repository'
try {
    $env0 = Initialize-PikoEnv -RepoRoot $RepoRoot -Quiet
    Ok 'Location' $env0.RepoRoot
} catch {
    Bad 'Location' $_.Exception.Message
    Write-Host ''; Write-Host "RESULT: FAILED ($($script:Failures) problem(s))" -ForegroundColor Red
    exit 1
}

Push-Location $env0.RepoRoot
try {
    $branch  = (git rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
    $commit  = (git rev-parse --short HEAD 2>$null | Out-String).Trim()
    $origin  = (git remote get-url origin 2>$null | Out-String).Trim()
    $upstream= (git remote get-url upstream 2>$null | Out-String).Trim()
    if ($branch) { Ok 'Branch' "$branch @ $commit" } else { Bad 'Branch' 'not a git repository' }
    if ($origin -match 'github\.com')   { Ok 'origin' $origin }   else { Bad 'origin' 'missing - expected your fork' }
    if ($upstream -match 'crimera')     { Ok 'upstream' $upstream } else { Warn 'upstream' 'missing - expected https://github.com/crimera/piko.git' }

    $pushDefault = (git config --get remote.pushDefault 2>$null | Out-String).Trim()
    if ($pushDefault -eq 'origin') { Ok 'remote.pushDefault' 'origin (pushes never reach upstream)' }
    else { Warn 'remote.pushDefault' "is '$pushDefault'; run: git config remote.pushDefault origin" }

    $dirty = (git status --porcelain 2>$null | Out-String).Trim()
    if ($dirty) { Warn 'Working tree' "has local modifications:`n$dirty" } else { Ok 'Working tree' 'clean' }

    # ------------------------------------------------------------------ wrapper
    Head 'Gradle wrapper'
    if (Test-Path (Join-Path $env0.RepoRoot 'gradlew.bat')) { Ok 'gradlew.bat' 'present' } else { Bad 'gradlew.bat' 'missing' }
    if (Test-Path (Join-Path $env0.RepoRoot 'gradle\wrapper\gradle-wrapper.jar')) { Ok 'gradle-wrapper.jar' 'present' } else { Bad 'gradle-wrapper.jar' 'missing' }
    $wrapperProps = Join-Path $env0.RepoRoot 'gradle\wrapper\gradle-wrapper.properties'
    if (Test-Path $wrapperProps) {
        $dv = (Select-String -Path $wrapperProps -Pattern 'gradle-([0-9.]+)-(bin|all)\.zip' | Select-Object -First 1)
        if ($dv) { Ok 'Gradle version' $dv.Matches[0].Groups[1].Value } else { Warn 'Gradle version' 'could not parse distributionUrl' }
    }

    # --------------------------------------------------------------------- jdk
    Head 'Java'
    if ($env0.JavaHome) {
        Ok 'JAVA_HOME' $env0.JavaHome
        if ($env0.JavaMajor -ge 21)     { Ok 'Java version' "$($env0.JavaMajor) (meets Morphe requirement of 21+)" }
        elseif ($env0.JavaMajor -ge 17) { Warn 'Java version' "$($env0.JavaMajor) - builds (Piko CI uses 17) but Morphe documents 21+" }
        else                            { Bad 'Java version' "$($env0.JavaMajor) - need 17 minimum, 21+ recommended" }
    } else { Bad 'JAVA_HOME' 'no JDK found; run install-toolchain.ps1' }

    $sysJava = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
    if ($sysJava) { Ok 'System JAVA_HOME' "$sysJava (left untouched by these scripts)" }

    # -------------------------------------------------------------- android sdk
    Head 'Android SDK'
    if ($env0.AndroidSdk) {
        Ok 'ANDROID_HOME' $env0.AndroidSdk

        $requiredPlatform = 'android-36'   # compileSdk = 36 across the extension modules
        $platforms = @(Get-ChildItem -Path (Join-Path $env0.AndroidSdk 'platforms') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        if ($platforms -contains $requiredPlatform) { Ok 'platforms' ($platforms -join ', ') }
        else { Bad 'platforms' "$requiredPlatform missing (have: $($platforms -join ', '))" }

        $bt = @(Get-ChildItem -Path (Join-Path $env0.AndroidSdk 'build-tools') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        if ($bt.Count -gt 0) { Ok 'build-tools' ($bt -join ', ') } else { Bad 'build-tools' 'none installed' }

        if (Test-Path (Join-Path $env0.AndroidSdk 'platform-tools')) { Ok 'platform-tools' 'present' } else { Warn 'platform-tools' 'missing (only needed for adb/install)' }

        $lic = @(Get-ChildItem -Path (Join-Path $env0.AndroidSdk 'licenses') -File -ErrorAction SilentlyContinue)
        if ($lic.Count -gt 0) { Ok 'licences' "$($lic.Count) accepted" } else { Bad 'licences' 'none accepted' }
    } else { Bad 'ANDROID_HOME' 'no Android SDK found; run install-toolchain.ps1' }

    # ------------------------------------------------------- github packages auth
    Head 'GitHub Packages (Morphe registry)'
    $probeUrl = 'https://maven.pkg.github.com/MorpheApp/registry/app/morphe/patches/app.morphe.patches.gradle.plugin/1.3.4/app.morphe.patches.gradle.plugin-1.3.4.pom'
    $credSource = $null
    $user = $null; $pass = $null

    $gradleProps = Join-Path $env:USERPROFILE '.gradle\gradle.properties'
    if (Test-Path $gradleProps) {
        $props = @{}
        Get-Content $gradleProps | ForEach-Object {
            if ($_ -match '^\s*([A-Za-z0-9_.\-]+)\s*=\s*(.+?)\s*$') { $props[$Matches[1]] = $Matches[2] }
        }
        if ($props['gpr.user'] -and $props['gpr.key']) {
            $user = $props['gpr.user']; $pass = $props['gpr.key']
            $credSource = "~\.gradle\gradle.properties"
        }
    }
    if (-not $pass) {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if ($gh) {
            $tok = (& gh auth token 2>$null | Out-String).Trim()
            if ($tok -and $tok.Length -gt 20) {
                $user = (& gh api user --jq .login 2>$null | Out-String).Trim()
                $pass = $tok
                $credSource = 'GitHub CLI keyring (gh auth token)'
                $scopes = (& gh auth status 2>&1 | Out-String)
                if ($scopes -notmatch 'read:packages|write:packages') {
                    Warn 'gh token scopes' 'read:packages NOT granted - run: gh auth refresh -h github.com -s read:packages'
                }
            }
        }
    }
    if ($credSource) { Ok 'Credentials' $credSource } else { Bad 'Credentials' 'none found (gpr.user/gpr.key or gh CLI)' }

    if ($pass) {
        $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($user):$($pass)"))
        try {
            $r = Invoke-WebRequest -Uri $probeUrl -Headers @{ Authorization = "Basic $auth" } -UseBasicParsing -TimeoutSec 45
            if ($r.StatusCode -eq 200) { Ok 'Registry probe' 'app.morphe.patches:1.3.4 reachable (HTTP 200)' }
            else { Bad 'Registry probe' "unexpected HTTP $($r.StatusCode)" }
        } catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 401) { Bad 'Registry probe' 'HTTP 401 - token lacks read:packages. Run: gh auth refresh -h github.com -s read:packages' }
            elseif ($code -eq 404) { Bad 'Registry probe' 'HTTP 404 - plugin version changed upstream; check gradle/libs.versions.toml and settings.gradle.kts' }
            else { Bad 'Registry probe' "unreachable ($($_.Exception.Message))" }
        }
    } else { Bad 'Registry probe' 'skipped - no credentials' }

    # ------------------------------------------------------------------ network
    Head 'Network'
    foreach ($target in @(
        @{ n = 'services.gradle.org'; u = 'https://services.gradle.org/distributions/' },
        @{ n = 'repo.maven.apache.org'; u = 'https://repo.maven.apache.org/maven2/' },
        @{ n = 'dl.google.com'; u = 'https://dl.google.com/android/repository/repository2-3.xml' }
    )) {
        try {
            $r = Invoke-WebRequest -Uri $target.u -Method Head -UseBasicParsing -TimeoutSec 25
            if ([int]$r.StatusCode -lt 400) { Ok $target.n "HTTP $([int]$r.StatusCode)" } else { Bad $target.n "HTTP $([int]$r.StatusCode)" }
        } catch {
            $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
            # Some endpoints reject HEAD; a 403/405 still proves connectivity.
            if ($code -in 403, 405) { Ok $target.n "reachable (HTTP $code on HEAD)" }
            else { Bad $target.n $_.Exception.Message }
        }
    }

    # ------------------------------------------------------------- optional deep
    if ($Deep) {
        Head 'Gradle configuration (deep check)'
        if (-not $env0.JavaHome -or -not $env0.AndroidSdk) {
            Bad 'gradlew help' 'skipped - JDK or Android SDK missing'
        } else {
            $deepLog = Join-Path $PSScriptRoot 'logs\verify-gradle-help.log'
            New-Item -ItemType Directory -Force -Path (Split-Path $deepLog -Parent) | Out-Null
            cmd /c "`"$($env0.GradlewPath)`" help --console=plain 2>&1" | Out-File -FilePath $deepLog -Encoding utf8
            if ($LASTEXITCODE -eq 0) { Ok 'gradlew help' 'build configures and the Morphe plugin resolves' }
            else {
                Bad 'gradlew help' "exit $LASTEXITCODE - see $deepLog"
                Get-Content $deepLog -Tail 25 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
            }
        }
    }
}
finally { Pop-Location }

Head 'Result'
if ($script:Failures -eq 0) {
    Write-Host ("READY - 0 failed, {0} warning(s). Build with: .\build-piko.ps1" -f $script:Warnings) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("FAILED - {0} failed, {1} warning(s)." -f $script:Failures, $script:Warnings) -ForegroundColor Red
    exit 1
}
