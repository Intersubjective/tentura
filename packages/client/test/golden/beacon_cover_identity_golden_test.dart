import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

/// Serves a deterministic in-memory PNG so photo identity actually paints.
class _CoverHttpOverrides extends HttpOverrides {
  _CoverHttpOverrides(this.pngBytes);

  final Uint8List pngBytes;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(pngBytes);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.pngBytes);

  final Uint8List pngBytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(pngBytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.pngBytes);

  final Uint8List pngBytes;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async =>
      _FakeHttpClientResponse(pngBytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse implements HttpClientResponse {
  _FakeHttpClientResponse(this.pngBytes);

  final Uint8List pngBytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => pngBytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(pngBytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<Uint8List> _solidPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder, const Rect.fromLTWH(0, 0, 16, 16))
    ..drawRect(
      const Rect.fromLTWH(0, 0, 16, 16),
      ui.Paint()..color = const Color(0xFF2E7D32),
    )
    ..drawRect(
      const Rect.fromLTWH(0, 0, 16, 8),
      ui.Paint()..color = const Color(0xFFFFC107),
    );
  final image = await recorder.endRecording().toImage(16, 16);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

const _coverImage = ImageEntity(
  id: 'cover-1',
  authorId: 'author-1',
  width: 16,
  height: 16,
);

Beacon _beacon({
  String? primaryNeedSlug,
  Set<String> needs = const {},
  List<ImageEntity> images = const [],
  String? coverImageId,
  BeaconCoverSource coverSource = BeaconCoverSource.photo,
}) =>
    Beacon.empty.copyWith(
      id: 'b-cover',
      title: 'Move two boxes across town on Friday afternoon',
      context: 'Neighborhood',
      author: const Profile(id: 'author-1', displayName: 'Fionna Campbell'),
      needs: needs,
      images: images,
      primaryNeedSlug: primaryNeedSlug,
      coverImageId: coverImageId,
      coverSource: coverSource,
    );

final _photoBeacon = _beacon(
  images: const [_coverImage],
  coverImageId: 'cover-1',
  needs: const {'transport'},
  primaryNeedSlug: 'transport',
);

final _symbolBeacon = _beacon(
  needs: const {'transport'},
  primaryNeedSlug: 'transport',
  coverSource: BeaconCoverSource.symbol,
);

final _neutralBeacon = _beacon();

void main() {
  setUpAll(() async {
    HttpOverrides.global = _CoverHttpOverrides(await _solidPng());
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpGolden(
    WidgetTester tester, {
    required String name,
    required Widget body,
    required Size logicalSize,
    required Brightness brightness,
    double textScaler = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: brightness == Brightness.light
            ? TenturaTheme.light()
            : TenturaTheme.dark(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: logicalSize,
            textScaler: TextScaler.linear(textScaler),
          ),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: const Key('golden'),
                    child: SizedBox(width: logicalSize.width, child: body),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the in-memory network image resolve before capturing.
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/beacon_cover_$name.png'),
    );
  }

  group('identity branches', () {
    for (final brightness in Brightness.values) {
      for (final size in <double>[32, 40, 56]) {
        testWidgets(
          '${brightness.name} at ${size.toInt()}px',
          (tester) async {
            await pumpGolden(
              tester,
              name: 'branches_${brightness.name}_${size.toInt()}',
              logicalSize: const Size(360, 200),
              brightness: brightness,
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  spacing: 16,
                  children: [
                    BeaconIdentityTile(beacon: _photoBeacon, size: size),
                    BeaconIdentityTile(beacon: _symbolBeacon, size: size),
                    BeaconIdentityTile(beacon: _neutralBeacon, size: size),
                  ],
                ),
              ),
            );
          },
        );
      }
    }
  });

  group('capability groups', () {
    for (final brightness in Brightness.values) {
      testWidgets('seven group swatches in ${brightness.name}', (tester) async {
        final oneTagPerGroup = <CapabilityTag>[
          CapabilityTag.transport,
          CapabilityTag.calls,
          CapabilityTag.localKnowledge,
          CapabilityTag.childcare,
          CapabilityTag.food,
          CapabilityTag.software,
          CapabilityTag.other,
        ];

        await pumpGolden(
          tester,
          name: 'capability_groups_${brightness.name}',
          logicalSize: const Size(420, 160),
          brightness: brightness,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              spacing: 12,
              children: [
                for (final tag in oneTagPerGroup)
                  TenturaCapabilityGlyph(tag: tag, size: 40),
              ],
            ),
          ),
        );
      });
    }
  });

  group('card header identity', () {
    for (final width in <double>[320, 700, 1200]) {
      testWidgets('header row at ${width.toInt()}px', (tester) async {
        await pumpGolden(
          tester,
          name: 'card_header_${width.toInt()}',
          logicalSize: Size(width, 700),
          brightness: Brightness.light,
          body: Column(
            children: [
              for (final beacon in <Beacon>[
                _photoBeacon,
                _symbolBeacon,
                _neutralBeacon,
              ])
                BeaconCardShell(
                  child: BeaconCardHeaderRow(
                    beacon: beacon,
                    menu: const SizedBox(width: 32, height: 40),
                  ),
                ),
            ],
          ),
        );
      });
    }
  });

  testWidgets('card header at text scale 2.0', (tester) async {
    await pumpGolden(
      tester,
      name: 'card_header_320_s2_0',
      logicalSize: const Size(320, 900),
      brightness: Brightness.light,
      textScaler: 2,
      body: Column(
        children: [
          for (final beacon in <Beacon>[_photoBeacon, _neutralBeacon])
            BeaconCardShell(
              child: BeaconCardHeaderRow(
                beacon: beacon,
                menu: const SizedBox(width: 32, height: 40),
              ),
            ),
        ],
      ),
    );
  });
}
