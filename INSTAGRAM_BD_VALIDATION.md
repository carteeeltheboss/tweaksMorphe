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

Final report: `output/reports/instagram-452-complete-bd.json`.
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
- DEX hook/settings audit: PASS (`logs/combined-bd-dex-audit.log`).
- `adb devices`: no device. Original Saved BD was previously tested successfully
  by the user. New select-all, Profile BD and restored settings need device QA.

Final APK: `output/instagram-452-complete-bd.apk` (Instagram 452.1.0.53.64).
SHA256: 500a31fe1afd597180a4f89b51faed2e26e44f4502ea6bfcb62a531c4a2984c7.
Build log: `logs/combined-bd-build-final.log`.
Patch log: `logs/combined-bd-final.log`.

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

