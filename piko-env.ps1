<#
.SYNOPSIS
    Shared environment resolver for the Piko helper scripts. Dot-source this file; do not run it.

.DESCRIPTION
    Locates the Piko repository, a suitable JDK, and the Android SDK, then exports the environment
    variables Gradle needs (JAVA_HOME, ANDROID_HOME, ANDROID_SDK_ROOT) plus GitHub Packages
    credentials for the current process only.

    Nothing here writes to disk and nothing here modifies your source tree.

    Resolution order (first hit wins):
      Repository   : -RepoRoot parameter > $env:PIKO_REPO > <script dir>\piko
      JDK          : $env:PIKO_JAVA_HOME > $env:JAVA_HOME (if >= 21) > %USERPROFILE%\dev-tools\jdk-21
                     > %ProgramFiles%\Eclipse Adoptium\jdk-21* / jdk-17*
      Android SDK  : $env:PIKO_ANDROID_HOME > $env:ANDROID_HOME > %LOCALAPPDATA%\Android\Sdk
                     > %USERPROFILE%\Android\Sdk
      GitHub auth  : gpr.user/gpr.key in ~\.gradle\gradle.properties, else `gh auth token`
                     exported as GITHUB_ACTOR / GITHUB_TOKEN for this process only.

.NOTES
    Deliberately does NOT change the machine-wide JAVA_HOME: other projects on this machine may
    depend on the system JDK 17. The JDK is scoped to the build process instead.
#>

# Resolve the directory this file lives in (works when dot-sourced from PS 5.1 and PS 7).
if ($PSScriptRoot) {
    $script:PikoToolsRoot = $PSScriptRoot
} else {
    $script:PikoToolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Resolve-PikoRepo {
    param([string]$RepoRoot)

    $candidates = @()
    if ($RepoRoot)                       { $candidates += $RepoRoot }
    if ($env:PIKO_REPO)                  { $candidates += $env:PIKO_REPO }
    $candidates += (Join-Path $script:PikoToolsRoot 'piko')
    $candidates += $script:PikoToolsRoot

    foreach ($candidate in $candidates) {
        if ((Test-Path (Join-Path $candidate 'gradlew.bat')) -and (Test-Path (Join-Path $candidate 'settings.gradle.kts'))) {
            return (Resolve-Path $candidate).Path
        }
    }
    throw ("Could not find the Piko repository. Looked in: " + ($candidates -join '; ') +
           ". Set `$env:PIKO_REPO or pass -RepoRoot.")
}

function Get-PikoJavaHome {
    <#
        Returns the best JDK on this machine. Prefers one that meets $MinimumMajor (default 21)
        over an older one, because morphe-desktop's jar is compiled for Java 21 and fails with
        UnsupportedClassVersionError on 17 - while Piko itself builds on either.

        Deliberately does NOT trust $env:JAVA_HOME ahead of the known JDK 21 locations: a shell
        opened before the toolchain was installed has JAVA_HOME pointing at the machine-wide JDK 17
        and no PIKO_JAVA_HOME at all.
    #>
    param([int]$MinimumMajor = 21)

    $candidates = @()
    if ($env:PIKO_JAVA_HOME) { $candidates += $env:PIKO_JAVA_HOME }
    $candidates += (Join-Path $env:USERPROFILE 'dev-tools\jdk-21')

    foreach ($root in @('C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java',
                        'C:\Program Files\Microsoft', 'C:\Program Files\Zulu')) {
        if (Test-Path $root) {
            $candidates += (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match '^jdk-(2[1-9]|[3-9][0-9])' } |
                            ForEach-Object { $_.FullName })
        }
    }
    # Whatever the environment says, then any JDK at all - an older one beats none for Piko.
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    foreach ($root in @('C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java')) {
        if (Test-Path $root) {
            $candidates += (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match '^jdk-' } |
                            ForEach-Object { $_.FullName })
        }
    }

    $fallback = $null
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not ($candidate -and (Test-Path (Join-Path $candidate 'bin\java.exe')))) { continue }
        $major = Get-PikoJavaVersion -JavaHome $candidate
        if ($major -ge $MinimumMajor) { return $candidate }
        if (-not $fallback) { $fallback = $candidate }
    }
    return $fallback
}

function Get-PikoJavaVersion {
    param([string]$JavaHome)
    if (-not $JavaHome) { return $null }
    $java = Join-Path $JavaHome 'bin\java.exe'
    if (-not (Test-Path $java)) { return $null }
    $raw = cmd /c "`"$java`" -version 2>&1" | Select-Object -First 1
    if ($raw -match 'version "(\d+)(?:\.(\d+))?') { return [int]$Matches[1] }
    if ($raw -match 'version "1\.(\d+)')          { return [int]$Matches[1] }
    return $null
}

function Get-PikoAndroidSdk {
    $candidates = @()
    if ($env:PIKO_ANDROID_HOME) { $candidates += $env:PIKO_ANDROID_HOME }
    if ($env:ANDROID_HOME)      { $candidates += $env:ANDROID_HOME }
    if ($env:ANDROID_SDK_ROOT)  { $candidates += $env:ANDROID_SDK_ROOT }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    $candidates += (Join-Path $env:USERPROFILE 'Android\Sdk')

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate 'platforms'))) { return $candidate }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function Initialize-PikoEnv {
    param([string]$RepoRoot, [switch]$Quiet)

    $repo = Resolve-PikoRepo -RepoRoot $RepoRoot

    $javaHome = Get-PikoJavaHome
    $javaMajor = Get-PikoJavaVersion -JavaHome $javaHome
    $sdkRoot  = Get-PikoAndroidSdk

    if ($javaHome) {
        $env:JAVA_HOME = $javaHome
        $env:Path = (Join-Path $javaHome 'bin') + ';' + $env:Path
    }
    if ($sdkRoot) {
        $env:ANDROID_HOME     = $sdkRoot
        $env:ANDROID_SDK_ROOT = $sdkRoot
    }

    # GitHub Packages credentials. settings.gradle.kts reads gpr.user/gpr.key, falling back to
    # GITHUB_ACTOR/GITHUB_TOKEN. Prefer the existing gradle.properties; otherwise borrow the
    # GitHub CLI token from the OS keyring so no secret is ever written to disk.
    $gradleProps = Join-Path $env:USERPROFILE '.gradle\gradle.properties'
    $haveFileCreds = $false
    if (Test-Path $gradleProps) {
        $content = Get-Content -Path $gradleProps -Raw -ErrorAction SilentlyContinue
        if ($content -match '^\s*gpr\.key\s*=\s*\S' -and $content -match '^\s*gpr\.user\s*=\s*\S') {
            $haveFileCreds = $true
        }
    }
    if (-not $haveFileCreds) {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if ($gh) {
            $token = (& gh auth token 2>$null | Out-String).Trim()
            if ($token -and $token.Length -gt 20) {
                if (-not $env:GITHUB_ACTOR) {
                    $user = (& gh api user --jq .login 2>$null | Out-String).Trim()
                    if ($user) { $env:GITHUB_ACTOR = $user }
                }
                $env:GITHUB_TOKEN = $token
            }
        }
    }

    if (-not $Quiet) {
        Write-Host "Repository : $repo"
        Write-Host "JAVA_HOME  : $(if ($javaHome) { $javaHome } else { '<not found>' }) (Java $(if ($javaMajor) { $javaMajor } else { '?' }))"
        Write-Host "ANDROID_HOME: $(if ($sdkRoot) { $sdkRoot } else { '<not found>' })"
        Write-Host "GitHub Packages auth: $(if ($haveFileCreds) { 'gradle.properties (gpr.user/gpr.key)' } elseif ($env:GITHUB_TOKEN) { 'gh CLI token (process-scoped)' } else { '<none>' })"
    }

    return [pscustomobject]@{
        RepoRoot      = $repo
        JavaHome      = $javaHome
        JavaMajor     = $javaMajor
        AndroidSdk    = $sdkRoot
        HasFileCreds  = $haveFileCreds
        HasTokenCreds = [bool]$env:GITHUB_TOKEN
        GradlewPath   = (Join-Path $repo 'gradlew.bat')
        MppDirectory  = (Join-Path $repo 'patches\build\libs')
    }
}
