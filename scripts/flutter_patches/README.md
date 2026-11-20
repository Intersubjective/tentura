# Flutter and Dart SDK patches

## `flutter-195316-flush-semantics.patch` — #746, #916 (Flutter 3.47.0)

`Dockerfile.builder` applies this upstream patch to the cloned Flutter SDK
before the dev and prod web builds. The image build fails if it no longer applies.

- Bug: flutter/flutter#195316. With semantics on (dev and prod enable them),
  a push over a page whose geometry cache is left from an earlier push/pop
  throws `Null check operator used on a null value` in
  `_RenderObjectSemantics._buildSemantics` ← `PipelineOwner.flushSemantics`
  (Sentry TENTURA-CLIENT-4J/4V/5P). Repro on dev 7.60.18: open a request,
  Back, click «+» in My work.
- Fix: the `packages/flutter/lib/src/rendering/object.dart` hunk of
  flutter/flutter#192724, verbatim (unmerged when pinned; its test hunk is
  left out).
- Re-check on every Flutter upgrade: `bash scripts/check_flutter_semantics_patch.sh`
  warns when `FLUTTER_VERSION` in `Dockerfile.builder` is not the pinned one or
  when #192724 has merged. If the new Flutter has the fix, delete this patch
  and the apply step in `Dockerfile.builder`, and remove the check; else bump
  `PINNED_FLUTTER` in the check once the patch applies.
- Verify after deploy-dev: `node scripts/e2e_focus/semantics_push_null_check.mjs`
  (see `scripts/e2e_focus/README.md`): expect 0 null-check hits.

## Dart 3.13.0 analyzer telemetry

The Dart analyzer may cancel a pending Google Analytics connection during
shutdown from a different Dart error zone than the send. The
`dart-3.13.0-telemetry-zone.patch` keeps both network operations in the root
zone and preserves the SDK's existing treatment of failed telemetry requests.

To install it locally, use a Dart SDK source checkout at revision
`da6595cd6bb5d4c0a185d759a025e879ff06e631` with dependencies synced and
`.dart_tool/package_config.json` generated. Pass the root of the Dart SDK used
by the gate. For Flutter, that is `<flutter>/bin/cache/dart-sdk`.

For isolated verification, set `DART_SDK_SOURCE` to the prepared checkout.
Keep its package configuration and referenced dependency directories together
so the installer can rebuild the analyzer in a clean SDK copy.

```sh
python3 scripts/flutter_patches/install-dart-analyzer-patch.py <installed-dart-sdk> <dart-sdk-source>
./scripts/run_with_test_cleanup.sh --timeout 280s -- python3 -m unittest -v scripts.test_server_analysis_with_unreachable_telemetry
```

The installer retains the stock analyzer snapshot as
`bin/snapshots/analysis_server_aot.dart.snapshot.stock`. Restore that file over
the installed snapshot to undo the patch.
