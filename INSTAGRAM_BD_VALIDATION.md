# Instagram full-feature batch download validation

## Cause and patch selection evidence

The previous `instagram-452-bd.apk` was a restricted integration-test build:
`patch --exclusive -e "Saved Posts Batch Downloader"`. Its report contains only
that selected patch (plus implicit dependencies). No original patch or settings
initializer was removed from source. Delivering that test APK caused the missing
settings regression.

The retained known-good report is
`output/fresh-apkpure/reports/com.instagram.android_452.1.0.53.64.json`.
Its 65 applied patch names are preserved in `instagram-baseline.json`.
The existing general `patch-apks.ps1` never used `--exclusive` and remains intact.
The original available-patch inventory remains in `logs/morphe-list-patches-final.txt`;
the current bundle inventory is `logs/current-instagram-patches.txt`.
Available patches are not evidence of application; the comparisons below use
successful applied-patch reports.

| Artifact / stage | Applied patches | Missing baseline patches | Failed patches |
|---|---:|---:|---:|
| Original baseline | 65 | 0 | 0 |
| Earlier restricted Saved BD APK | 1 selected + dependencies | 65 named baseline selections | 0 |
| Restored full + Saved BD | 66 | 0 | 0 |
| Full + Saved Select All | 66 | 0 | 0 |
| Final full + both BD patches | 67 | 0 | 0 |

Final report: `output/reports/instagram-452-toolbar-queue.json`.
The final DEX audit confirms the original SettingsStatus.load initialization,
including ghost/privacy/download/feed/theme flags, both lifecycle hooks, exactly
one shared thumbnail bind hook, and one profile click wrapper.
This is source/patch evidence, not a claim of runtime settings visibility.

## Behavior

Both named patches are independently selectable and share an unnamed grid-hook
dependency and the existing download engine. Selection belongs to each screen.
Profile ID changes clear selection; destroying a view clears screen state.
Retry controls are scoped to the originating screen and profile. An explicitly
started download continues after navigation with application context.

Select All Loaded reads native model data, including off-screen loaded items.
It never forces pagination. Scroll normally, then select all loaded again.
Profile enumeration reads compatible adapters beneath the current profile root;
it does not promise enumeration of detached tabs or the entire profile.
Deselect All and individual deselection remain available. Duplicate/pinned IDs
are merged. Carousels use the same complete-post path as Saved BD.

The native 452 model extraction uses 0fgo.CkC (complete Media), matching the
native Saved renderer. CMJ returns layout metadata and is not a media reference.
No authentication, privacy or content-access bypass is implemented.

## Validation performed

- `buildAndroid`, `:patches:checkStringResources` and
  `:extensions:instagram:testBatchDownload`: PASS.
- Selection tests: stable IDs, off-screen input, deduplication, independent stores,
  manual deselection, clear, snapshot independence: PASS.
- Queue tests: sequential processing, concurrent-start rejection, per-item
  failures, progress, cancellation and observer isolation: PASS.
- Final full patch application with `--validate --verify-with-sdk`: 67 applied,
  zero failed; signed APK generated and SDK APK verification completed.
- SDK D8 emits an internal NullPointerException on classes.dex, also present in
  baseline logs. Final classes.dex is byte-for-byte identical to the known-good
  baseline: SHA256 efaf32b5c3e62f365daa5efcfbd1561511b751a3fcf2e17806922873e0e91c09.
  This is a retained baseline verification limitation, not a clean D8 pass.
- DEX hook/settings audit: PASS (`logs/toolbar-queue-dex-audit.log`).
- `adb devices`: no device. Original Saved BD was previously tested successfully
  by the user. New select-all, Profile BD and restored settings need device QA.

Final APK: `output/instagram-452-toolbar-queue.apk` (Instagram 452.1.0.53.64).
SHA256: d6e621b3b5cb8ac2741759c2760df748cbc41065d5b3abd1d7325abb1efd514f.
Build log: `logs/toolbar-queue-build.log`.
Patch log: `logs/toolbar-queue-patch.log`.

## Reproduce

Run `./build-instagram-full.ps1` from the workspace root. It builds and patches all
default compatible features, then rejects reports missing any baseline or either
BD patch. Use `-SkipBuild` to reuse the current bundle. Supported input is 452;
no compatibility-force option is used. Default output is `output/instagram-452-full-bd.apk`.

For unit tests, initialize `piko-env.ps1`, enter `piko`, and run
`./gradlew.bat :extensions:instagram:testBatchDownload`.
For the DEX audit, run Java 21 source-file mode with the Morphe CLI fat JAR on the
classpath against `piko/extensions/instagram/tests/batchDownload/AuditCombined.java`,
passing the final APK path.

## Device QA still required

1. Install the signed final APK using the same signature/install procedure as the
   earlier patched app. Open Piko Settings and compare Ghost Mode, privacy, feed,
   download, theme and interface categories with the baseline.
2. Toggle one Ghost Mode option; verify its real behavior. Test a normal manual
   photo/video download and manual Download All on a mixed carousel.
3. Open Saved All Posts and a collection. BD: individually select, scroll several
   pages, scroll back, and confirm only the correct stable IDs remain checked.
4. Select All Loaded, manually deselect one, scroll to load more, select all loaded
   again, and Deselect All. Confirm no unloaded-page completion claim is shown.
5. Repeat on own/another authorized profile; include pinned posts and switch posts
   and Reels tabs. Confirm the native grid continues paginating normally.
6. Select on Profile A, navigate to Profile B, then Saved. Confirm no selections
   or retry actions leak between profiles or Saved.
7. Download a photo, video, Reel and mixed carousel. Count every carousel file.
   Interrupt connectivity: remaining posts should continue, failures should be
   counted, and retry should skip already completed files within partial posts.
8. Cancel a batch: the active file may finish; remaining queued files must stop.
   Navigate away during a batch and confirm Instagram remains responsive.
9. Open empty/private/deleted-content cases: no inaccessible posts should become
   available, and unavailable items should fail without crashing the app.


## Toolbar visibility fix and live download queue

The current test APK places a blue BD button immediately before the profile menu
inside 452's verified `right_action_bar_buttons` LinearLayout. It hooks native
configureActionBar (`UserDetailFragment.AeX`) and waits for view attachment/layout.
This fixes a source-level failure path where initial attachment silently returned
without a FrameLayout ancestor. Device confirmation is still required; no Android
runtime log establishing the exact cause of the earlier missing button was available.
The bottom selection controls appear after tapping BD. Long-press BD to open the
queue, or use Piko Settings -> Download Queue.

Manual and batch file requests share one serialized worker in Instagram. Duplicate
pending/active file keys reuse the same future. Other apps do not enable this queue.
The live queue shows pending/active/completed/failed/cancelled/skipped file records,
received bytes, known content length, last progress update age, sanitized error
type/message, and the latest batch's post states. Active files are listed first.
Cancel pending also cancels remaining batch posts; the active file finishes safely.
Clear file history preserves pending/active work. History is process-local and
retains the latest 200 finished files plus all pending/active records. It resets
when Instagram exits. Authentication URLs are not exposed in queue diagnostics.

Additional tests: `:extensions:instagram:testDownloadQueueMonitor` passed for state
transitions, byte progress, immutable snapshots, cancellation, timeout redaction,
skipped files, bounded finished history, and retention of queued work. Batch tests
also assert live post states and immediate pending-post cancellation. Final DEX
audit asserts the native toolbar hook, queue activation in Instagram settings,
and a reachable Download Queue settings entry. All 67 patches still applied.

For device QA, install `instagram-452-toolbar-queue.apk`, open your own and another
profile, and look immediately left of the top-right menu for blue BD. Select posts,
then open Piko Settings -> Download Queue (or long-press BD). While a batch is
active, request a manual download; confirm one active file and pending work. Test
slow/offline connectivity and inspect failure details; cancel pending and confirm
that the current file may finish while the rest stop. Close the queue and return
to the profile to verify native scrolling/clicks and selection cleanup still work.

Reproduce this filename with:
`./build-instagram-full.ps1 -OutputName instagram-452-toolbar-queue`.

## BD tools 3 visibility follow-up

The user confirmed the toolbar-queue APK was installed but neither new entry was
visible. No connected device/logcat was available to establish the precise runtime
failure. Do not treat successful patching as proof that the UI is visible.

Use `output/instagram-452-bd-tools3.apk` for the next device test. Download Queue now
uses Piko's styled ButtonPref, has a searchable key, and is first on both the main
Piko Settings page and Download Media page. Its summary says "BD tools 3". The old
plain preference lacked a search key and was absent from the Download Media page.

Profile BD now also hooks the verified native ProfileActionBar.A00 renderer, after
native menu construction. The toolbar button no longer depends on successful
fragment-screen registration to be displayed. If its screen association fails,
tapping it reports that explicitly. The queue includes profile creation/render
counters and the last toolbar attachment result for actionable device diagnostics.

Validation: buildAndroid, testBatchDownload, testDownloadQueueMonitor and
checkStringResources passed. Full APK patching applied all 67 patches with zero
failures; signed APK and DEX audit completed. Audit checks the new native toolbar
hook. The baseline D8 internal-error limitation remains. Device visibility and
click behavior require retesting. Logs: logs/bd-tools3-build.log,
logs/bd-tools3-patch.log, logs/bd-tools3-audit.log.

## BD tools 4 profile registration

Device report from tools 3: profile creation=0, toolbar render=23. The visible
button therefore had no registered selection screen. This is an implementation
failure, not user misuse. Move profile registration from before RETURN_VOID to
method entry, where native branches cannot skip it. Register a direct weak
association between each native toolbar and its owning screen, and remove it on
destruction. Keep the existing complete-post downloader and 67-patch baseline.

Next test APK: output/instagram-452-bd-tools4.apk. Settings/queue diagnostics show
BD tools 4. Build, both unit-test tasks, string-resource validation, full signed
patch application and SDK APK checks completed. The DEX audit now requires the
registration call in the first eight instructions of profile onViewCreated.
Logs: logs/bd-tools4-build.log, logs/bd-tools4-patch.log, logs/bd-tools4-audit.log.
The existing baseline D8 limitation remains. Device selection/scroll/download
behavior still requires confirmation; successful compilation does not prove it.
