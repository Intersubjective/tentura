// #816: on Firefox/WebKit a cover slot stayed empty for seconds: only the
// BlurHash shader was drawn until the network image decoded, and nothing at
// all with no hash. The slot now paints a token-coloured placeholder on its
// first frame at its final size, BlurHash above it, the image fading in over
// both; an error shows the same placeholder.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/beacon_image.dart';

/// An image provider whose load is driven by the test.
class _ControlledImage extends ImageProvider<_ControlledImage> {
  _ControlledImage(this.completer);

  final Completer<ImageInfo> completer;

  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_ControlledImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _ControlledImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(completer.future);
}

const _hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

Beacon _beacon({String blurHash = ''}) => Beacon.empty.copyWith(
  id: 'B816',
  author: const Profile(id: 'U816'),
  images: [
    ImageEntity(id: 'img-816', width: 400, height: 300, blurHash: blurHash),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: locale,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 300, child: child),
      ),
    ),
  ),
);

Finder get _placeholder => find.byKey(beaconImagePlaceholderKey);

void main() {
  // The app loads the BlurHash shader at boot (di_current.dart); without it
  // BlurHash throws on build.
  var shaderLoaded = false;
  setUpAll(() async {
    try {
      await BlurHash.loadShader();
      shaderLoaded = true;
    } on Object catch (_) {
      shaderLoaded = false;
    }
  });

  bool skipWithoutShader(String hash) {
    if (hash.isEmpty || shaderLoaded) return false;
    markTestSkipped('BlurHash shader could not be loaded in this test env');
    return true;
  }

  for (final hash in ['', _hash]) {
    final label = hash.isEmpty ? 'no blurhash' : 'a blurhash';

    testWidgets('first frame: placeholder at the final size ($label)', (
      tester,
    ) async {
      if (skipWithoutShader(hash)) return;
      final pending = Completer<ImageInfo>();
      await _pump(
        tester,
        BeaconImage(
          beacon: _beacon(blurHash: hash),
          imageProviderFor: (_) => _ControlledImage(pending),
        ),
      );

      expect(_placeholder, findsOneWidget);
      expect(tester.getSize(find.byType(BeaconImage)), const Size(300, 225));
      expect(tester.getSize(_placeholder), const Size(300, 225));
    });

    testWidgets('an image error shows the same placeholder ($label)', (
      tester,
    ) async {
      if (skipWithoutShader(hash)) return;
      final failing = Completer<ImageInfo>();
      await _pump(
        tester,
        BeaconImage(
          beacon: _beacon(blurHash: hash),
          imageProviderFor: (_) => _ControlledImage(failing),
        ),
      );
      failing.completeError(Exception('network down'));
      await tester.pump();
      await tester.pump();

      // The base layer plus the error builder's copy.
      expect(_placeholder, findsNWidgets(2));
      expect(tester.getSize(find.byType(BeaconImage)), const Size(300, 225));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the decoded image fades in with no size change', (
    tester,
  ) async {
    final loading = Completer<ImageInfo>();
    await _pump(
      tester,
      BeaconImage(
        beacon: _beacon(),
        imageProviderFor: (_) => _ControlledImage(loading),
      ),
    );
    final before = tester.getSize(find.byType(BeaconImage));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );

    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 3),
        Paint(),
      );
      return recorder.endRecording().toImage(4, 3);
    });
    loading.complete(ImageInfo(image: image!));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    expect(tester.getSize(find.byType(BeaconImage)), before);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('a Request card identity tile shows the placeholder while '
      'its photo loads (375×667, ru)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final beacon = _beacon().copyWith(
      coverImageId: 'img-816',
      coverSource: BeaconCoverSource.photo,
    );
    await _pump(
      tester,
      Center(child: BeaconIdentityTile(beacon: beacon)),
      locale: const Locale('ru'),
    );

    expect(_placeholder, findsOneWidget);
    expect(tester.getSize(_placeholder), const Size(48, 48));
    // Leave the test HTTP client's error behind this frame.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no images: the placeholder fills the slot', (tester) async {
    await _pump(
      tester,
      SizedBox(
        height: 120,
        child: BeaconImage(beacon: Beacon.empty.copyWith(id: 'B0')),
      ),
    );
    expect(_placeholder, findsOneWidget);
    expect(tester.getSize(_placeholder), const Size(300, 120));
  });
}
