# HANDOFF PROMPT — Piko (Morphe patches) development environment on Windows 11

> Paste everything below the line into a new AI agent. It is self-contained.
> Prepared 2026-11-15 by the previous agent. Every fact marked ✅ was verified by running a command;
> facts marked ⚠️ are believed true but were **not** re-verified — check them before relying on them.

---

## YOUR ROLE

You are an autonomous senior Android build engineer and Windows environment specialist.
You are taking over a **nearly finished** task. Do not redo completed work — **verify it, then finish
what is left.**

The human's goal: develop their own features for [Piko](https://github.com/crimera/piko) (Morphe
patches for Twitter/X and Instagram). The environment setup phase is essentially done; the remaining
work is listed in **§6 UNDONE**.

## NON-NEGOTIABLE RULES

1. **Execute, don't advise.** Run the commands. Do not hand back instructions.
2. **Never claim success without evidence.** Quote the exit code and the artifact path/size/hash.
   Verification is *graded* (see §5) — state which level you proved, never "it works".
3. **Do not weaken or delete Piko functionality** to make something pass. No suppressing errors,
   no `-x` skipping a check just to get exit 0.
4. **Upstream is read-only.** `upstream` = `crimera/piko`. Never push to it, never open a PR or a
   release against it unless the human explicitly asks. `remote.pushDefault=origin` is already set.
5. **Never commit or print secrets.** The GitHub token lives in the Windows keyring and in
   `%USERPROFILE%\.gradle\gradle.properties` (outside the repo). Do not copy it into the repo,
   into a log, or into chat output.
6. **Helper scripts stay in the workspace root — never inside `piko\`.** This keeps
   `git status` inside the clone permanently clean.
7. **Ask at most one short question, and only when genuinely blocked.** Otherwise pick the sensible
   default and record it as an ADR line in `DEVELOPMENT_SETUP.md §13`.
8. **If the same failure repeats twice, stop and report it.** Do not loop.
9. Terse chat output. No whole-file dumps — use targeted reads, edits and diffs.

## WHERE THINGS ARE

| | |
|---|---|
| Workspace root | `C:\Users\Karim\Documents\tweaksMorphe` |
| Repo clone | `C:\Users\Karim\Documents\tweaksMorphe\piko` |
| Morphe CLI clone | `C:\Users\Karim\Documents\tweaksMorphe\morphe-desktop` |
| Test inputs (user-supplied) | `C:\Users\Karim\Documents\tweaksMorphe\apkFiles\*.apkm` |
| Patch run output | `C:\Users\Karim\Documents\tweaksMorphe\output\` |
| All logs | `C:\Users\Karim\Documents\tweaksMorphe\logs\` |
| **Main guide — read this first** | `DEVELOPMENT_SETUP.md` (14 sections: toolchain, patch anatomy, adding a patch, Morphe testing, credentials, troubleshooting, ADRs, disk budget) |

## VERIFIED CURRENT STATE (as of 2026-11-15 ~15:20 local)

**Repository** ✅
- Branch `karim/dev`, created from `upstream/dev`, HEAD `13d6ccbfd5ab4bad7ef8c4f476f713cf01aef1d8`
  (`13d6ccbf` — "feat(Instagram): Add options for already downloaded media", 2026-11-14).
- `origin` = `https://github.com/carteeeltheboss/piko.git` (the human's fork, created this session)
- `upstream` = `https://github.com/crimera/piko.git`
- `remote.pushDefault=origin`, `push.default=current`, branch pulls from `upstream/dev`.
- `git status --porcelain` → **empty** (clean). `git diff --cached` → **empty** (nothing staged).
- `karim/dev` has **NOT** been pushed to the fork (`git ls-remote --heads origin karim/dev` → empty).
- Piko version in `gradle.properties` = `3.11.1`.

**Build artifact** ✅
- `piko\patches\build\libs\patches-3.11.1.mpp`
- 8,680,234 bytes (8.28 MB), written 2026-11-15 14:51:18
- SHA-256 `E49D52E74E3752C5BBD152D7E55BCAE4DED74C117B01DCABAB8873B51B857A79`
- Valid zip (PK header), 2011 entries: `classes.dex`, `extensions/{shared,twitter,instagram}.mpe`,
  plus resource trees.

**Toolchain** ✅
- Temurin **JDK 21.0.13+9** at `C:\Users\Karim\dev-tools\jdk-21` (user-local zip install, no admin).
- Temurin **JDK 17.0.20** at `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot` —
  pre-existing, and **machine-scope `JAVA_HOME` still points at it. Leave it alone.**
- Android SDK at `C:\Users\Karim\Android\Sdk`: cmdline-tools v19, platform-tools,
  `platforms;android-36`, `build-tools;36.0.0`, 8 licences accepted.
- Gradle **9.8.2** from the repo wrapper (never a global Gradle).
- Git 2.56.0.windows.4, GitHub CLI 2.103.3, account `carteeeltheboss`,
  scopes `gist, read:org, read:packages, repo, workflow`.
- Morphe CLI jar: `morphe-desktop\build\libs\morphe-desktop-2.2.0-dev.19-all.jar` (67,266,258 bytes).
- `C:` has ~200 GB free.

**User env vars (persisted, user scope)** ✅
`PIKO_JAVA_HOME`, `PIKO_ANDROID_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`.

## SCRIPT INVENTORY (workspace root)

| Script | Purpose |
|---|---|
| `piko-env.ps1` | Shared resolver, dot-sourced by the others. Finds repo/JDK/SDK, injects GitHub Packages creds process-scoped from the `gh` keyring. `Get-PikoJavaHome` **prefers a 21+ JDK over `$env:JAVA_HOME`**; accepts `-MinimumMajor`. |
| `verify-env.ps1 [-Deep]` | Non-destructive health check. `-Deep` also runs `gradlew help`. Exit 0 = ready. |
| `build-piko.ps1 [-Clean] [-GradleArgs …]` | Deletes stale `.mpp`, runs `gradlew buildAndroid`, verifies the fresh bundle (size, zip header, sha256), prints path. Exit 0/1/2/3. |
| `clean-build.ps1` | Thin wrapper → `build-piko.ps1 -Clean` (= `gradlew clean buildAndroid`, what CI runs). |
| `build-morphe-cli.ps1 [-Force]` | Clones/builds Morphe Desktop CLI, reports the `*-all.jar`. |
| `morphe.ps1` | Runs the Morphe CLI against the local bundle (`list-patches`, `list-versions`, patch). **Hard-fails below Java 21.** |
| `patch-apks.ps1 [-Install]` | Batch-patches every `apkFiles\*.apkm`, writes `output\` + `output\reports\*.json` + `output\README.md`. **Currently buggy — see §7.** |
| `install-toolchain.ps1` | Idempotent JDK 21 + Android SDK installer, no UAC. |
| `fresh-session-check.ps1` | Simulates a brand-new PowerShell session (env rebuilt from registry) and re-verifies. |

All scripts log into `logs\`. All return meaningful exit codes.

## §5 — VERIFICATION IS GRADED IN FOUR LEVELS

| # | Level | Status | Evidence |
|---|---|---|---|
| 1 | **Source compiles** | ✅ PROVEN (7+ runs) | `gradlew buildAndroid` exit 0; `:patches:checkStringResources` → "Verified 18335 strings, no issues found". Built OK on **both** JDK 17 (2m12s) and JDK 21 (2m41s). |
| 2 | **`.mpp` bundle produced** | ✅ PROVEN | File/size/hash above; valid zip, 2011 entries. |
| 3 | **Morphe accepts the bundle** | ✅ PROVEN | `morphe.ps1 list-patches` → **140 patches** (indices 0–139, 136 default-on, 4 opt-in); `list-versions` → `com.instagram.android 452.1.0.53.64`, `com.twitter.android 12.19.1-release.0` — matches Piko's README exactly. |
| 4 | **Patches a real app** | ❌ **FAILED — this is your main job** | `patch-apks.ps1` → **"0 patched, 2 failed"**. See §6 and §7. |

Also proven: a second build succeeds in the same environment; `verify-env.ps1 -Deep` exits 0.

## §6 — UNDONE WORK (in priority order)

### TASK 1 — Fix the two `patch-apks.ps1` defects so real errors surface  *(do this first)*
Acceptance: a failed patch run prints a numeric Morphe exit code, and `output\README.md` shows the
correct bundle size. See **§7** for exact locations and fixes.

### TASK 2 — Diagnose and resolve the Level-4 patching failure  *(the real blocker)*
The **supported** version `com.instagram.android 452.1.0.53.64` fails. Root cause already captured in
`logs\patch-com.instagram.android_452.1.0.53.64.log`:

```
com.android.tools.r8.CompilationFailedException: Compilation failed to complete
Caused by: java.lang.NullPointerException:
  Cannot invoke "com.android.tools.r8.internal.Np.u()"
  because the return value of "com.android.tools.r8.internal.dH.get(int)" is null
    at com.android.tools.r8.dex.U.a(...)
    ... at com.android.tools.r8.D8.main(...)
```
R8/D8 version in the trace: `R8_8.10.9-dev_f905a40d…`, running on Java 21, launched with
`java -Xms1024m -jar morphe-desktop-2.2.0-dev.19-all.jar`.

Hypotheses to test **in this order** (cheapest first):
1. **Heap.** Only `-Xms1024m` is set, no `-Xmx`. A 137 MB APKM being dexed can exhaust the default
   heap and surface as a bizarre R8 NPE. Try `-Xmx6g` (edit the `Invoke-Morphe` java args).
2. **JDK used to *run* the CLI.** Try a different 21.x build, and check whether Morphe documents a
   specific JDK. Note `morphe.ps1` hard-fails below 21, so don't just drop to 17 without editing it.
3. **Stale Morphe CLI.** The clone is `-b dev --depth 1` from 2026-11-15. Pull latest `dev`,
   rebuild via `build-morphe-cli.ps1 -Force`, retry. Search `MorpheApp/morphe-desktop` issues for
   this exact R8 NPE before assuming it's local.
4. **Input file integrity.** The 452 file is named `…_2dpi_…apkmirror.com (1).apkm` — a re-download.
   Piko's README says *do not unsplit or modify* the APKM. Re-download a clean copy of
   `com.instagram.android 452.1.0.53.64` if the file looks truncated. **Ask the human before
   downloading anything** — they supplied these files themselves.
5. **Not** the `455.0.0.51.72` file: the bundle only supports `452.1.0.53.64`, so that one failing
   is *expected*. Don't chase it. Consider making `patch-apks.ps1` skip unsupported versions with a
   clear SKIP status instead of FAILED.

Acceptance for TASK 2: Level 4 proven — `patch-apks.ps1` reports `1 patched` for 452.1.0.53.64,
produces a non-empty signed APK, and you state its path/size/sha256. If it is genuinely an upstream
Morphe/R8 bug, **stop and report that** with the evidence and the issue link — do not hack around it.

### TASK 3 — Clean up the misleading failed artifact
`output\patched_com.instagram.android_455.0.0.51.72.apk` (155.6 MB) exists even though that run
**FAILED**. A partial file next to real successes is a trap. Delete it, and make
`patch-apks.ps1` remove/quarantine output when the exit code is non-zero.

### TASK 4 — Optional, needs the human's decision (do NOT do unprompted)
- **Install on a device/emulator** to finish Level 4 end-to-end. `platform-tools\adb.exe` is present;
  no emulator/system image is installed (~1–2 GB each). The patched APK is signed with Morphe's key,
  so it installs *alongside*, not over, a Play Store install — or use Piko's Instagram "Clone" patch.
- **Push `karim/dev` to the fork** (`git push -u origin karim/dev`). Not done. Pushing to *their own*
  fork is safe; still confirm first. No PR, no release.
- **Install IntelliJ IDEA / Android Studio** for Kotlin+Gradle IDE support (~1 GB). VS Code is
  already set up per `DEVELOPMENT_SETUP.md §9`. If you do, set the Gradle JDK to
  `C:\Users\Karim\dev-tools\jdk-21`.
- **Start actual feature development** — the human's real objective. `DEVELOPMENT_SETUP.md §6`
  documents the patch anatomy and where to add files.

## §7 — KNOWN DEFECTS (exact locations)

**Defect A — exit code stringifies to `System.Object[]`** in `patch-apks.ps1` (~line 94):

```powershell
function Invoke-Morphe {
    param([string[]]$CliArgs, [string]$LogPath)
    & $java '-Xms1024m' '-jar' $jar.FullName @CliArgs 2>&1 |
        ForEach-Object { $_.ToString() } | Tee-Object -FilePath $LogPath
    return $LASTEXITCODE
}
```
`Tee-Object` passes objects through to the success stream, so the function returns
*the teed lines **plus*** `$LASTEXITCODE` → an array → renders as `System.Object[]` in
`output\README.md` (`| Outcome | **FAILED** (Morphe exit System.Object[]) |`).
Fix: terminate the pipeline and capture the code separately, e.g.
`… | Tee-Object -FilePath $LogPath | Out-Host` then `$exit = $LASTEXITCODE; return $exit`.

**Defect B — bundle size prints as `0 MB`** in the generated `output\README.md`
(`**Patch bundle:** … (0 MB, sha256 …)` although the file is 8.28 MB). The sha256 next to it is
correct, so only the size formatting is wrong. Find the README-generation block in `patch-apks.ps1`
(near the `| Outcome |` line ~245) and fix the MB rounding. ⚠️ Exact line not verified.

**Non-defect, don't "fix" it:** `verify-env.ps1` warns `Java version 17` in shells that predate the
JDK 21 install, because machine `JAVA_HOME` intentionally still points at 17. Both JDKs build Piko.
Scope the JDK per build; never repoint machine `JAVA_HOME`.

## §8 — ENVIRONMENT TRAPS (each one already cost time)

1. **GitHub Packages auth is mandatory.** `settings.gradle.kts` resolves the `app.morphe.patches`
   plugin (v1.3.4) and `app.morphe:morphe-patches-library` (2.2.0-dev.4) from
   `https://maven.pkg.github.com/MorpheApp/registry`. These are **not** on Maven Central or the
   Gradle Plugin Portal (verified 404). Without `read:packages` you get **HTTP 401** — not 404.
   Already fixed via `gh auth refresh -h github.com -s read:packages` (interactive device flow —
   only the human can approve it). Credentials are in
   `%USERPROFILE%\.gradle\gradle.properties` as `gpr.user` / `gpr.key`, and scripts also inject
   `GITHUB_ACTOR`/`GITHUB_TOKEN` from the keyring.
2. **`%USERPROFILE%\.gradle\gradle.properties` also carries**
   `org.gradle.java.installations.paths=C:/Users/Karim/dev-tools/jdk-21,C:/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot`
   (forward slashes — `.properties` eats backslashes). Without it Gradle can't find the non-standard
   JDK 21 location and downloads a ~500 MB duplicate into `~\.gradle\jdks`. **Do not delete this line.**
3. **`morphe-desktop-*-all.jar` is Java 21 bytecode.** Running it with the machine default JDK 17
   → `UnsupportedClassVersionError (class file version 65.0 vs 61.0)`. That's why
   `Get-PikoJavaHome` prefers 21+.
4. **`C:` filled to 0 bytes once during setup**, breaking builds with ENOSPC
   (`java.io.IOException: There is not enough space on the disk`). Now ~200 GB free.
   Check `(Get-PSDrive C).Free/1GB` before any new heavyweight download and report the number.
   Budget: Piko's whole `build` output is only ~63 MB; `morphe-desktop` needs ~1–1.5 GB.
   `~\.gradle\caches` (~1 GB) is a last resort. `D:` has only ~3 GB free — not a relocation target.
5. **PowerShell 5.1 gotchas that already bit:** `java -version` writes to stderr, so under
   `$ErrorActionPreference='Stop'` a bare `2>&1` becomes a terminating error — wrap native commands
   in `cmd /c "… 2>&1"`. And `$PSScriptRoot` is **empty while param defaults are being bound**, so
   resolve it in the body (`if (-not $CloneRoot) { $CloneRoot = $PSScriptRoot }`).
6. **A shell opened before the install has no `PIKO_JAVA_HOME`.** Use `fresh-session-check.ps1` to
   test the "new terminal" path rather than trusting the current process env.

## §9 — COMMANDS YOU WILL NEED

```powershell
cd C:\Users\Karim\Documents\tweaksMorphe

.\verify-env.ps1 -Deep        # health check, exit 0 = ready
.\build-piko.ps1              # incremental build -> .mpp
.\clean-build.ps1             # gradlew clean buildAndroid (what CI runs)
.\build-morphe-cli.ps1        # rebuild the Morphe CLI jar
.\morphe.ps1 list-patches     # prove Morphe reads the bundle (Level 3)
.\morphe.ps1 list-versions
.\patch-apks.ps1              # Level 4 - CURRENTLY FAILING
.\fresh-session-check.ps1     # verify from a clean environment

# raw Gradle, if you need it:
cd piko; .\gradlew.bat buildAndroid
cd piko; .\gradlew.bat :patches:checkStringResources
```

## §10 — DEFINITION OF DONE FOR YOU

1. `patch-apks.ps1` reports a **numeric** exit code and a correct bundle size (TASK 1).
2. Level 4 is either **proven** for `com.instagram.android 452.1.0.53.64` (patched APK path + size +
   sha256 stated), **or** conclusively shown to be an upstream Morphe/R8 defect with evidence and a
   link — no third option, no vague "should work".
3. No misleading partial artifacts left in `output\` (TASK 3).
4. `piko` clone still `git status --porcelain` clean, nothing staged, nothing pushed, no PR, no release.
5. `verify-env.ps1 -Deep` still exits 0 and `build-piko.ps1` still produces a valid `.mpp`
   (prove you didn't regress Levels 1–3).
6. `DEVELOPMENT_SETUP.md` updated for anything you changed, with any new default recorded as an ADR
   line in §13. No secret ever written into the repo, a log, or chat.

## §11 — REPORT BACK LIKE THIS

```
LEVELS PROVEN: 1 ✅  2 ✅  3 ✅  4 <✅/❌ + one-line evidence>
CHANGED:      <files + what/why, or "none">
BLOCKED ON:   <exact error + what you need from the human, or "nothing">
NEXT:         <the one thing you'd do next>
```
Keep it to ~5 lines. Do not paste whole logs — give the path and the relevant tail.

## §12 — DO NOT TRUST THESE (unverified / stale-risk)

- ⚠️ Defect B's exact line number in `patch-apks.ps1`.
- ⚠️ Whether `morphe-desktop` `dev` has moved since the 2026-11-15 clone (it was `--depth 1`).
- ⚠️ The 140-patch / supported-version figures — true for bundle `E49D52E7…` at commit `13d6ccbf`.
  If you rebuild after new commits, re-run `morphe.ps1 list-patches` rather than quoting these.
- ⚠️ Anything in this file older than 2026-11-15. Re-verify with `verify-env.ps1 -Deep` first.
