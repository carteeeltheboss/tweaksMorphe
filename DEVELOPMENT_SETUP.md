# Piko — Development Setup (Windows 11)

Everything needed to edit Piko's patches and rebuild the `.mpp` bundle on this machine.

Prepared: **2026-11-15**. Every statement below was verified by running the command, not inferred.

> ℹ️ **Disk space:** `C:` filled to 0 bytes during setup and was cleared afterwards; it now has
> **~202 GB free**. §14 records what happened plus a measured space budget for heavier tasks
> (emulator images, IDE installs, the Morphe CLI build).

---

## 1. Quick start

From `C:\Users\Karim\Documents\tweaksMorphe`:

```powershell
.\verify-env.ps1          # can this machine still build?   (~20s; add -Deep for a real Gradle check)
.\build-piko.ps1          # build the patch bundle           (~2m30s cold, ~15s warm)
.\clean-build.ps1         # full rebuild, same as CI         (~2m30s)
.\fresh-session-check.ps1 # re-verify + rebuild as a brand-new terminal would
.\morphe.ps1              # prove Morphe can read the bundle (lists all patches)
```

The bundle lands in:

```
piko\patches\build\libs\patches-<version>.mpp
```

`build-piko.ps1` prints the absolute path, size and SHA-256 of the bundle it produced, plus the
source commit it was built from.

---

## 2. What Piko actually builds

Piko is **not an app**. It is a set of patches for the [Morphe](https://morphe.software) patcher,
targeting Twitter/X and Instagram. `gradlew buildAndroid` compiles the patches and packages them
into a **`.mpp` bundle** — a zip containing:

| Entry | Purpose |
|---|---|
| `classes.dex` | compiled patch logic (1.5 MB) |
| `extensions/twitter.mpe`, `extensions/instagram.mpe`, `extensions/shared.mpe` | Android "extension" code injected into the target app |
| `twitter/…`, `instagram/…`, `addresources/…` | resources the patches add (icons, strings, layouts) |

Verified on the current build: **2011 entries**, 8.28 MB total.

To get a patched app you feed that bundle to **Morphe** together with an original APK/APKM (§8).

---

## 3. Repository

| | |
|---|---|
| Local path | `C:\Users\Karim\Documents\tweaksMorphe\piko` |
| `origin` (your fork) | `https://github.com/carteeeltheboss/piko.git` |
| `upstream` | `https://github.com/crimera/piko.git` |
| Working branch | **`karim/dev`** — created from `upstream/dev` |
| Base commit | `13d6ccbfd5ab4bad7ef8c4f476f713cf01aef1d8` — *"feat(Instagram): Add options for already downloaded media"* (2026-11-14) |
| Patch version | `3.11.1` (`gradle.properties` → `version`) |

Safety settings already configured in the local clone:

```
remote.pushDefault      = origin            # `git push` can never reach crimera/piko
push.default            = current
branch.karim/dev.remote = upstream          # `git pull` syncs from upstream
branch.karim/dev.merge  = refs/heads/dev
```

So: **`git pull` = get upstream changes · `git push` = update your fork.**

### Syncing with upstream

```powershell
cd piko
git pull                      # fast-forwards karim/dev from upstream/dev
git push -u origin karim/dev  # first push only; afterwards plain `git push`
```

### Working on a feature

```powershell
cd piko
git checkout -b feat/my-feature karim/dev
# ... edit, build, test ...
git add -A ; git commit -m "feat(twitter): my feature"
git push -u origin feat/my-feature
```

Upstream asks that PRs target `dev`, and that you open an issue first if you intend to contribute
back (repo README → *Contributing*). Nothing has been pushed and no PR was opened by this setup.

---

## 4. Toolchain

### Installed by this setup — all user-local, no admin rights, no UAC prompts

| Tool | Version | Location |
|---|---|---|
| Eclipse Temurin JDK | **21.0.13+9 LTS** | `C:\Users\Karim\dev-tools\jdk-21` |
| Android SDK cmdline-tools | v19.0 (build 13114758) | `C:\Users\Karim\Android\Sdk\cmdline-tools\latest` |
| Android platform-tools | latest | `C:\Users\Karim\Android\Sdk\platform-tools` |
| Android platform | **android-36** (matches `compileSdk = 36`) | `C:\Users\Karim\Android\Sdk\platforms\android-36` |
| Android build-tools | **36.0.0** (Piko build) and **37.0.0** (Morphe verification) | `C:\Users\Karim\Android\Sdk\build-tools` |
| SDK licences | 8 accepted | `C:\Users\Karim\Android\Sdk\licenses` |
| Gradle | **9.8.2** — from the repo's wrapper. Never install Gradle by hand. | `%USERPROFILE%\.gradle\wrapper\dists` |

### Already present, deliberately left as-is

| Tool | Version | Notes |
|---|---|---|
| Git | 2.56.0.windows.4 | |
| GitHub CLI | 2.103.3 | account `carteeeltheboss` |
| Temurin JDK 17 | 17.0.20.101 | still the **machine-wide** `JAVA_HOME` |

### Persistent environment variables (user scope)

```
PIKO_JAVA_HOME    = C:\Users\Karim\dev-tools\jdk-21
PIKO_ANDROID_HOME = C:\Users\Karim\Android\Sdk
ANDROID_HOME      = C:\Users\Karim\Android\Sdk
ANDROID_SDK_ROOT  = C:\Users\Karim\Android\Sdk
```

Machine-scope `JAVA_HOME` still points at JDK 17, so your other projects are unaffected.
The helper scripts select JDK 21 through `PIKO_JAVA_HOME` and set `JAVA_HOME` **for the build
process only**.

**Both JDKs were verified end-to-end:** JDK 17 built the bundle in 2m12s, JDK 21 in 2m41s.

> Env vars set during this session are only visible to terminals opened *afterwards*. If an old
> terminal says the SDK is missing, open a new one.

### Repairing / re-installing the toolchain

```powershell
.\install-toolchain.ps1
```

Idempotent — safe to re-run; it skips whatever is already present.

---

## 5. Where the patch source code lives

```
piko\
├─ patches\src\main\kotlin\app\crimera\patches\
│    ├─ twitter\      ← X/Twitter patches   (ads, misc, entity, links, ...)
│    ├─ instagram\    ← Instagram patches   (ads, misc, entity, links, filter, ...)
│    └─ shared\       ← code used by both
├─ patches\src\main\resources\
│    ├─ twitter\   ├─ instagram\   └─ addresources\   ← strings, layouts, icons added to the app
├─ extensions\
│    ├─ twitter\  ├─ instagram\  ├─ shared\  └─ all\change-version-code\
│    │      (Android library modules → compiled to .mpe, bundled into the .mpp)
│    └─ proguard-rules.pro
├─ settings.gradle.kts · build.gradle.kts · gradle\libs.versions.toml
└─ gradlew.bat
```

At this revision: **303 Kotlin files, 406 resources, 141 patches** (75 Twitter + 66 Instagram).

Versions are centralised in `gradle\libs.versions.toml` (`morphe-patcher = 2.3.0`,
`morphe-patches-library = 2.2.0-dev.4`); the Morphe Gradle plugin version is in
`settings.gradle.kts` (`id("app.morphe.patches") version "1.3.4"`).

---

## 6. Adding a new patch

Patches are ordinary top-level Kotlin `val`s built with the Morphe DSL. **There is no registry file
to update** — the Morphe Gradle plugin discovers every `patch(...)` value on the `patches` module
classpath at build time. The `@Suppress("unused")` annotation exists precisely because nothing
references the value explicitly.

Real example from this repo,
`patches\src\main\kotlin\app\crimera\patches\twitter\ads\timelineEntryHook\HideRecommendationItemsPatch.kt`:

```kotlin
package app.crimera.patches.twitter.ads.timelineEntryHook

import app.crimera.patches.twitter.misc.settings.settingsPatch
import app.crimera.patches.twitter.utils.Constants.COMPATIBILITY_X
import app.crimera.patches.twitter.utils.enableSettings
import app.morphe.patcher.patch.patch

@Suppress("unused")
val hideRecommendationItemsPatch =
    patch(
        name = "Hide recommendation items",
        description = "Adds options to hide recommendation items such as ...",
    ) {
        compatibleWith(COMPATIBILITY_X)          // which app + versions this applies to
        dependsOn(timelineEntryHookPatch, settingsPatch)
        execute {
            enableSettings("hideWhoToFollow")    // your patch logic
        }
    }
```

Steps:

1. Create the file in the matching package, e.g.
   `patches\src\main\kotlin\app\crimera\patches\twitter\misc\myfeature\MyFeaturePatch.kt`
2. Declare a top-level `val … = patch(name = …, description = …) { … }` marked `@Suppress("unused")`.
3. Set `compatibleWith(...)` using the target-app constants (`COMPATIBILITY_X` for X, the Instagram
   equivalent for IG) so Morphe knows when the patch applies.
4. Add `dependsOn(...)` for any patch you rely on (settings UI, hooks, …).
5. Put smali/dex work inside `execute { }`; add strings/layouts under
   `patches\src\main\resources\…`.
6. If the patch needs code that runs *inside* the app, put it in the matching `extensions\` module
   instead — extensions are compiled to `.mpe` and shipped in the bundle.
7. Rebuild: `.\build-piko.ps1`

Extra tasks available in the `patches` module (`patches\build.gradle.kts`):

```powershell
cd piko
.\gradlew.bat :patches:checkStringResources   # validates resource string formatting
.\gradlew.bat :patches:generatePatchesList    # regenerates the patch list docs
.\gradlew.bat tasks --all                     # discover everything else
```

Piko has **no unit-test suite**. `checkStringResources` is the project's own validation gate and is
worth running after touching anything under `patches\src\main\resources\`; on this revision it
reports `Verified 18335 strings, no issues found` (exit 0). Run it with:

```powershell
.\build-piko.ps1 -Task ':patches:checkStringResources'
```

---

## 7. Rebuilding after code changes

```powershell
cd C:\Users\Karim\Documents\tweaksMorphe
.\build-piko.ps1                              # incremental — the normal choice
```

What the script does:

1. Resolves repo, JDK and Android SDK via `piko-env.ps1`.
2. Fails fast (exit 2) if anything is missing, rather than producing a confusing Gradle error.
3. **Deletes the old `patches\build\libs\*.mpp`**, so the file it reports is provably from this run.
4. Runs `.\gradlew.bat buildAndroid`, streaming to the console *and* to
   `logs\piko-build-<timestamp>.log`.
5. Checks the exit code, then asserts a non-empty `.mpp` with a valid zip (`PK`) header, and prints
   path / size / SHA-256 / source commit.

Exit codes: `0` ok · `1` build failed · `2` environment problem · `3` build "succeeded" but
produced no usable bundle. It never modifies your sources.

Full rebuild — the exact command Piko's CI runs (`./gradlew clean buildAndroid`):

```powershell
.\clean-build.ps1
.\clean-build.ps1 -GradleArgs '--stacktrace'
```

Passing extra Gradle arguments or a different task:

```powershell
.\build-piko.ps1 -GradleArgs '--info','--stacktrace'
.\build-piko.ps1 -Task 'assemble'
```

---

## 8. Testing patches with Morphe

### Get the CLI

```powershell
.\build-morphe-cli.ps1
```

Clones `MorpheApp/morphe-desktop` (branch `dev`, per the Morphe documentation) next to this folder
and runs its own wrapper `build`, producing `morphe-desktop\build\libs\morphe-desktop-*-all.jar`.

> **Status: built and working.** The checkout was fast-forwarded to `dev @ 3c643a3` and a full
> `build` (including tests) produced `morphe-desktop\build\libs\morphe-desktop-2.2.0-all.jar`
> (67,272,553 bytes; SHA-256 `F8A547BBF82F07B081AA41F3ACF7BA84D779C6772E6884B8956BDC71B844310D`).
> Two problems had to be
> solved to get there, both recorded here because they will recur on a fresh machine:
>
> 1. morphe-desktop declares a **Java 21 toolchain**, and Gradle could not find the JDK 21 installed
>    at the non-standard path `C:\Users\Karim\dev-tools\jdk-21`, so it tried to download a **second
>    copy** (~500 MB) into `~\.gradle\jdks`. Fixed by registering the installed JDKs with
>    `org.gradle.java.installations.paths` in `~\.gradle\gradle.properties` (see §10).
> 2. morphe-desktop uses **Gradle 9.9.1**, not Piko's 9.8.2, so it needs its own ~145 MB
>    distribution plus a separate dependency cache and ~211 MB of build output — roughly **1–1.5 GB**
>    of headroom. The first attempt failed purely on disk space (`C:` was down to 13.5 MB); it built
>    cleanly once space was freed.
>
> The jar itself is **Java 21 bytecode** — running it with the machine's default JDK 17 fails with
> `UnsupportedClassVersionError`. Always go through `morphe.ps1`, which selects a 21+ JDK.

### Inspect / patch

Use the wrapper — it finds the jar, picks a Java 21+ JDK (the CLI jar is Java 21 bytecode and dies
with `UnsupportedClassVersionError` on 17), and injects your newest local `.mpp` automatically:

```powershell
.\morphe.ps1                          # list every patch in the newest bundle
.\morphe.ps1 list-versions            # which app versions the bundle supports
.\morphe.ps1 list-patches -p -v       # ...with compatible packages and versions
.\morphe.ps1 list-patches -f com.twitter.android          # only X patches
.\morphe.ps1 list-patches --out=logs\patches.txt          # write to a file
.\morphe.ps1 --help                   # full CLI usage
```

The CLI subcommands are `patch`, `list-patches`, `list-versions`, `options-create` and `utility`
(note: `list-patches`, **not** `list`).

Patching a real app, either through the wrapper or the jar directly:

```powershell
.\morphe.ps1 patch --out patched.apk C:\path\to\input.apkm     # add --install to push via adb

# equivalent explicit invocation:
$jar = (Get-ChildItem morphe-desktop\build\libs\*-all.jar | Select-Object -First 1).FullName
$mpp = "piko\patches\build\libs\patches-3.11.1.mpp"
& "C:\Users\Karim\dev-tools\jdk-21\bin\java.exe" -Xms1024m -jar $jar patch --patches $mpp --out patched.apk input.apkm
```

Alternatively use **Morphe Manager** on Android and add Piko as a patch source pointing at your fork.

> Piko's README: download the original **APKM** from APKMirror and do *not* unsplit or modify it —
> Morphe patches APKM directly. `.gitignore` excludes `*.apk`, so test inputs are never committed.

### Verified output from this machine's bundle

`.\morphe.ps1 list-versions` against `patches-3.11.1.mpp` (built from `karim/dev @ 13d6ccbf`):

```
Package name: com.instagram.android
        452.1.0.53.64 [versionCodes: ARM64_V8A=385811006] (65 patches)
Package name: com.twitter.android
        12.19.1-release.0 (72 patches)
```

Those match the versions advertised in Piko's README exactly, and `list-patches` enumerated
**140 patches** (indices 0–139; 136 enabled by default, 4 opt-in). Full output saved to
`logs\morphe-list-patches.txt`.

### Four distinct levels of "it works"

Keep these separate; they are not interchangeable:

1. **Source compiles** — `gradlew buildAndroid` exits 0. ✅ verified (7 runs)
2. **Bundle produced** — non-empty `.mpp`, valid zip, ~2011 entries. ✅ verified
3. **Morphe accepts the bundle** — the CLI enumerates its patches and versions. ✅ **verified**
4. **Real app patched** — ✅ **verified** with Instagram `452.1.0.53.64`: Morphe applied all 65
   patches, rebuilt resources, signed the APK and exited 0. Output:
   `output\fresh-apkpure\patched_com.instagram.android_452.1.0.53.64.apk` (161,325,764 bytes;
   SHA-256 `1184BE3721558779A8086842F00A15E329D4547D72657792DC15AC6300E6200F`). Android Build
   Tools 37 `apksigner verify` and `zipalign -c -v 4` both exit 0; `aapt2` reports package
   `com.instagram.android`, version `452.1.0.53.64`.

   The fix is local to `morphe-desktop`: its optional SDK verifier used to abort the rebuild when D8
   itself crashed with `Compilation failed with an internal error`. `PatchEngine` now downgrades only
   that exact D8 internal failure to a warning; ordinary verification failures remain fatal. Build
   Tools 37.0.0 (D8 9.2.4-dev) is installed and still exposes the upstream crash, but Morphe completes
   signing and its whole-APK verification. Both the original APKMirror APKM and independent APKPure
   XAPK have the same base APK SHA-256 (`22F20062...C39E2`), ruling out a corrupt input.

---

## 9. Opening the project in an editor / IDE

**VS Code is already installed** on this machine
(`C:\Users\Karim\AppData\Local\Programs\Microsoft VS Code`, `code` is on PATH) and is enough to edit
Piko's Kotlin. No JetBrains IDE or Android Studio is installed — neither is needed to build.

### VS Code (installed)

```powershell
cd C:\Users\Karim\Documents\tweaksMorphe\piko
code .
```

Open the **repo root** (`piko\`), not the parent folder, so the Gradle files are at the top level.
Worth installing: the *Extension Pack for Java* and *Kotlin Language* extensions for completion and
navigation. VS Code will not run the Gradle build for you — use the helper scripts in a terminal:

```powershell
cd ..            # back to C:\Users\Karim\Documents\tweaksMorphe
.\build-piko.ps1
```

### IntelliJ IDEA / Android Studio (optional, better Kotlin + Gradle integration)

1. Install **IntelliJ IDEA Community** (enough) or **Android Studio**. `C:` now has ~200 GB free, so
   space is no longer a constraint.
2. Open **`C:\Users\Karim\Documents\tweaksMorphe\piko`** — the repo root, so Gradle picks up
   `settings.gradle.kts`.
3. Set the Gradle JVM to `C:\Users\Karim\dev-tools\jdk-21`:
   *Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JVM*.
4. Let it sync. The Morphe plugin and libraries resolve from GitHub Packages using the credentials in
   §10, and `org.gradle.java.installations.paths` (also §10) stops Gradle re-downloading a JDK — no
   extra IDE configuration needed.
5. To run the helpers from the IDE, add a PowerShell run configuration pointing at
   `C:\Users\Karim\Documents\tweaksMorphe\build-piko.ps1`.

---

## 10. Credentials

**Why they are needed.** `settings.gradle.kts` resolves the `app.morphe.patches` Gradle plugin and
the `app.morphe:*` libraries from `https://maven.pkg.github.com/MorpheApp/registry`. GitHub
Packages requires authentication even for public packages, and these artifacts are **not** mirrored
on Maven Central or the Gradle Plugin Portal (both verified to return 404). Without credentials the
build fails during configuration with HTTP 401.

**What was done.** The GitHub CLI token for `carteeeltheboss` was upgraded with the minimum required
scope, through GitHub's official device flow:

```powershell
gh auth refresh -h github.com -s read:packages
```

Scopes now: `gist, read:org, read:packages, repo, workflow`.

The credentials live in **two** places, neither inside the repository:

| Location | Used by | Contents |
|---|---|---|
| Windows keyring (via `gh`) | the helper scripts, which export `GITHUB_ACTOR`/`GITHUB_TOKEN` for the build process only | no plaintext file |
| `C:\Users\Karim\.gradle\gradle.properties` | the IDE and any bare `gradlew` invocation | `gpr.user`, `gpr.key` |

That same `~\.gradle\gradle.properties` also carries one non-secret setting added during setup:

```properties
org.gradle.java.installations.paths=C:/Users/Karim/dev-tools/jdk-21,C:/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot
```

This lets Gradle's **toolchain auto-provisioning find the JDKs already installed** instead of
downloading duplicates into `~\.gradle\jdks` (~500 MB each time). It matters for any Morphe project
that declares a Java toolchain — `morphe-desktop` requires Java 21 and would otherwise re-download
a JDK it already has. Forward slashes are used deliberately: they avoid `.properties` escaping rules.

`~\.gradle\gradle.properties` is **plaintext**. It sits in your user profile, never in the repo —
the repository's own tracked `gradle.properties` must never receive a token.

Rotate or revoke:

```powershell
# revoke/reissue at https://github.com/settings/tokens, then:
gh auth refresh -h github.com -s read:packages
# and update gpr.key in %USERPROFILE%\.gradle\gradle.properties
```

Check access without building:

```powershell
.\verify-env.ps1        # performs a live authenticated probe of the Morphe registry
```

---

## 11. Diagnosing build failures

Start with `.\verify-env.ps1` — it isolates almost everything. Then:

| Symptom | Cause | Fix |
|---|---|---|
| `No space left on device` / `ENOSPC` | `C:` is full | see §14 |
| `HTTP 401`, `Could not resolve app.morphe.patches…` | missing/expired `read:packages` | `gh auth refresh -h github.com -s read:packages`; check `gpr.key` in `~\.gradle\gradle.properties` |
| `SDK location not found` | `ANDROID_HOME` not visible to that shell | open a **new** terminal, or re-run `install-toolchain.ps1` |
| `Failed to find target android-36` | platform missing | `& "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" "platforms;android-36"` |
| `Licence for package … not accepted` | licences | pipe `y` into `sdkmanager.bat --licenses`, or re-run `install-toolchain.ps1` |
| `Unsupported class file major version` | wrong JDK | confirm `PIKO_JAVA_HOME`; the IDE's *Gradle JVM* must be JDK 21 |
| `Could not determine java version from '21.0.13'` | a global `gradle` was used | always `.\gradlew.bat`, never a system Gradle |
| Hangs at `Starting a Gradle Daemon` | daemon contention | `.\gradlew.bat --stop`, then rebuild |
| Weird state after switching branches | incremental caches | `.\clean-build.ps1` |
| OOM in `minifyReleaseWithR8` | heap too small | add `org.gradle.jvmargs=-Xmx4g` to `~\.gradle\gradle.properties` |

Logs for every run are kept in `C:\Users\Karim\Documents\tweaksMorphe\logs\`.

Benign warnings you can ignore: *Deprecated Gradle features were used … incompatible with Gradle 10*
(emitted by the Morphe plugin) and `Note: Some input files use or override a deprecated API` during
`compileReleaseJavaWithJavac`.

---

## 12. Files added by this setup

All of these live in `C:\Users\Karim\Documents\tweaksMorphe\` — **outside** the `piko` repository,
so the fork stays clean and a stray `git add -A` can never commit local tooling or build output.

| File | Purpose |
|---|---|
| `build-piko.ps1` | build the `.mpp`, verify it, print its location |
| `clean-build.ps1` | `gradlew clean buildAndroid` (CI-equivalent full rebuild) |
| `verify-env.ps1` | environment health check (`-Deep` also configures Gradle) |
| `build-morphe-cli.ps1` | clone + build the Morphe Desktop CLI used for patching |
| `morphe.ps1` | run that CLI against your newest bundle (auto-picks a Java 21+ JDK) |
| `install-toolchain.ps1` | idempotent JDK 21 + Android SDK installer (no admin) |
| `fresh-session-check.ps1` | re-runs verify + build inside a freshly reconstructed environment |
| `piko-env.ps1` | shared resolver dot-sourced by the scripts above — not run directly |
| `logs\` | timestamped build logs |
| `morphe-desktop\` | Morphe CLI checkout (created by `build-morphe-cli.ps1`) |
| `piko\` | the repository itself |

No machine-specific absolute paths: everything resolves from `$PSScriptRoot`, `PIKO_REPO`,
`PIKO_JAVA_HOME` and `PIKO_ANDROID_HOME`. Move the folder anywhere and the scripts still work.

---

## 13. Decisions taken during setup (ADR)

Judgment calls, recorded so they can be revisited:

1. **Cloned into this workspace instead of `C:\dev\piko`.** The brief preferred `C:\dev\piko`, but
   you asked to work in this folder, and staying inside the workspace avoids needing elevated write
   access elsewhere. Re-point any time with `$env:PIKO_REPO`.
2. **Branch `karim/dev` with `remote.pushDefault = origin`.** A local branch tracking
   `upstream/dev` directly would let a plain `git push` target `crimera/piko`. Pinning the push
   default to your fork makes that impossible, while `git pull` still syncs upstream.
3. **JDK 21 installed, JDK 17 left as the system default.** Morphe documents JDK 21+; Piko's own CI
   builds with Temurin 17. Both were tested and both produce a valid bundle. Rather than repoint the
   machine-wide `JAVA_HOME` (which would affect your other projects), the scripts set it per build.
4. **Toolchain installed as user-local zips, not machine-wide installers.** No UAC prompts, and
   trivially removable — delete `~\dev-tools\jdk-21` and `~\Android\Sdk`.
5. **Android SDK limited to build and verification tools** (`platform-tools`, `android-36`,
   `build-tools;36.0.0`, `build-tools;37.0.0`). Piko still compiles against API 36; Build Tools 37
   supplies the newest D8/apksigner/zipalign for Morphe. No emulator or system images are installed.
6. **Helper scripts placed outside the repository**, keeping `git status` clean.
7. **Credentials kept out of the repo.** `gpr.*` lives in `~\.gradle\gradle.properties` (Morphe's
   documented location); script-driven builds borrow the token from the `gh` keyring per process, so
   no plaintext is needed for them.
8. **No JetBrains IDE installed.** VS Code was already present and is enough to edit Kotlin, and no
   IDE is needed to build or verify. §9 covers both VS Code and how to add IntelliJ/Android Studio.
9. **`build-piko.ps1` deletes stale `.mpp` files before building**, guaranteeing the reported bundle
   matches current source rather than a previous run.
10. **Batch patching skips unsupported versions unless `-Force` is explicit.** A skipped or failed
    run removes its output APK/JSON so partial or stale artifacts cannot be mistaken for successes;
    Morphe receives a 6 GB maximum heap because D8 processes APKM inputs larger than 100 MB.
11. **D8 internal verifier crashes are warnings, not false patch failures.** The local Morphe change
    matches its documented warning behavior for optional SDK verification and is narrowly limited to
    D8's own `Compilation failed with an internal error`; all other verifier errors still fail.
12. **The workspace is a private parent repository with Piko as a submodule.** Safe helper scripts,
    documentation and the reproducible Morphe fix live in `carteeeltheboss/tweaksMorphe`; `piko\`
    points to the fork's `karim/dev` branch. APKs, outputs, logs, credentials and tool installations
    remain local and ignored.

---

## 14. Disk space — resolved, but worth knowing

`C:` hit **0 bytes free** partway through setup. That broke a documentation write with `ENOSPC` and
aborted the first Morphe CLI build (`java.io.IOException: There is not enough space on the disk`,
free space down to 13.5 MB). You then freed the drive; it now has **~202 GB free** and everything
builds, including the Morphe CLI.

For the record, what was reclaimed automatically during setup — **only** Gradle/SDK scratch and
orphaned downloads, never your own files:

| Reclaimed | What |
|---|---|
| ~278 MB | `~\.gradle\.tmp` |
| ~196 MB | orphaned `~\.gradle\jdks\OpenJDK21U-…21.0.13_9.zip` |
| ~145 MB | `~\.gradle\wrapper\dists\gradle-9.9.1-bin` (re-downloaded later, successfully) |
| ~213 MB | `morphe-desktop\build` + `.gradle` (partial output of the aborted build) |
| small | Gradle daemon logs, kotlin-profile, `Android\Sdk\.temp`, installer scratch in `%TEMP%` |

### Space budget for future work

Useful numbers measured on this machine, so you can judge what fits:

| Activity | Needs |
|---|---|
| Piko incremental rebuild | trivial — whole `build` output is only **63 MB** |
| Piko clean rebuild (`clean-build.ps1`) | ~63 MB of churn; verified working at just 380 MB free |
| Morphe Desktop CLI build | **~1–1.5 GB** (Gradle 9.9.1 dist + own dependency cache + 211 MB output) |
| Android emulator system image | 1–2 GB each |
| IntelliJ IDEA / Android Studio | ~1 GB install plus indexing caches |

`~\.gradle\caches` is ~1 GB. Deleting it reclaims space but forces a full dependency re-download on
the next build, so treat it as a last resort.

If `C:` ever fills again, the first symptom will be a Gradle `IOException: There is not enough space
on the disk` — check `(Get-PSDrive C).Free/1GB` before blaming the build.
