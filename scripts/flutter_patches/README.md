# Flutter patches carried in the builder image

`Dockerfile.builder` (the image the dev and prod web builds run in) applies
these to the cloned Flutter SDK right after `git clone`; the image build fails
when one no longer applies. Each one is an upstream fix that was not in a
Flutter release when we pinned it.

## `flutter-195316-flush-semantics.patch` — #746, #916 (Flutter 3.47.0)

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
