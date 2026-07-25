import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

const _image = ImageEntity(id: 'img-1', authorId: 'author-1');

Beacon _beacon({
  String? primaryNeedSlug,
  Set<String> needs = const {},
  List<ImageEntity> images = const [],
  String? coverImageId,
  BeaconCoverSource coverSource = BeaconCoverSource.photo,
  bool canReadContent = true,
}) =>
    Beacon.empty.copyWith(
      id: 'beacon-1',
      title: 'Bring a van on Friday',
      author: const Profile(id: 'author-1'),
      needs: needs,
      images: images,
      primaryNeedSlug: primaryNeedSlug,
      coverImageId: coverImageId,
      coverSource: coverSource,
      canReadContent: canReadContent,
    );

Future<void> _pump(
  WidgetTester tester,
  Beacon beacon, {
  double size = 40,
  Brightness brightness = Brightness.light,
}) =>
    tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: brightness == Brightness.light
            ? TenturaTheme.light()
            : TenturaTheme.dark(),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Center(
              child: BeaconIdentityTile(beacon: beacon, size: size),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('photo identity renders the cover image', (tester) async {
    await _pump(
      tester,
      _beacon(images: const [_image], coverImageId: 'img-1'),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(TenturaCapabilityGlyph), findsNothing);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
  });

  testWidgets('symbol identity renders the capability glyph', (tester) async {
    await _pump(
      tester,
      _beacon(
        needs: const {'transport'},
        primaryNeedSlug: 'transport',
        coverSource: BeaconCoverSource.symbol,
      ),
    );

    expect(find.byType(TenturaCapabilityGlyph), findsOneWidget);
    expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
  });

  testWidgets('neutral identity renders the campaign glyph', (tester) async {
    await _pump(tester, _beacon());

    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.byType(TenturaCapabilityGlyph), findsNothing);
  });

  testWidgets('an unreadable request never shows photo or capability', (
    tester,
  ) async {
    await _pump(
      tester,
      _beacon(
        images: const [_image],
        coverImageId: 'img-1',
        needs: const {'transport'},
        primaryNeedSlug: 'transport',
        canReadContent: false,
      ),
    );

    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.byType(TenturaCapabilityGlyph), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a failed cover image degrades to the primary symbol', (
    tester,
  ) async {
    final beacon = _beacon(
      images: const [_image],
      coverImageId: 'img-1',
      needs: const {'housing'},
      primaryNeedSlug: 'housing',
    );
    await _pump(tester, beacon);

    final imageWidget = tester.widget<Image>(find.byType(Image));
    final fallback = imageWidget.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('offline'),
      null,
    );

    expect(fallback, isA<TenturaCapabilityGlyph>());
    expect((fallback as TenturaCapabilityGlyph).size, 40);
  });

  testWidgets('a failed cover image with no primary degrades to neutral', (
    tester,
  ) async {
    await _pump(
      tester,
      _beacon(images: const [_image], coverImageId: 'img-1'),
    );

    final imageWidget = tester.widget<Image>(find.byType(Image));
    final fallback = imageWidget.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('offline'),
      null,
    );

    expect(fallback, isNot(isA<TenturaCapabilityGlyph>()));
    await tester.pumpWidget(MaterialApp(home: fallback));
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
  });

  group('frame geometry is identical across identity branches', () {
    for (final size in <double>[32, 40, 56]) {
      testWidgets('exactly ${size.toInt()}x${size.toInt()}', (tester) async {
        for (final beacon in <Beacon>[
          _beacon(images: const [_image], coverImageId: 'img-1'),
          _beacon(needs: const {'transport'}, primaryNeedSlug: 'transport'),
          _beacon(),
        ]) {
          await _pump(tester, beacon, size: size);
          final box = tester.getSize(find.byType(TenturaIdentityTileFrame));
          expect(box.width, size);
          expect(box.height, size);
        }
      });
    }
  });

  testWidgets('semantics keep the title and append the capability label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await _pump(tester, _beacon());
    expect(find.bySemanticsLabel('Bring a van on Friday'), findsOneWidget);

    await _pump(
      tester,
      _beacon(needs: const {'transport'}, primaryNeedSlug: 'transport'),
    );
    expect(
      find.bySemanticsLabel('Bring a van on Friday, Transport'),
      findsOneWidget,
    );

    handle.dispose();
  });
}
