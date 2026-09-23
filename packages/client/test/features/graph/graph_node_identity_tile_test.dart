import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/beacon_image.dart';

Beacon _beacon({
  ImageEntity? coverThumb,
  BeaconCoverSource coverSource = BeaconCoverSource.photo,
  Set<String> needs = const {},
  String? primaryNeedSlug,
}) =>
    Beacon.empty.copyWith(
      id: 'B1',
      title: 'Need a ride',
      author: const Profile(id: 'U1'),
      coverThumb: coverThumb,
      coverSource: coverSource,
      needs: needs,
      primaryNeedSlug: primaryNeedSlug,
    );

Future<void> _pumpNode(WidgetTester tester, NodeDetails node) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Center(
            child: GraphNodeWidget(nodeDetails: node),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('GraphNodeWidget request identity', () {
    testWidgets('BeaconNode uses BeaconIdentityTile not BeaconImage', (
      tester,
    ) async {
      await _pumpNode(
        tester,
        BeaconNode(
          beacon: _beacon(
            coverThumb: const ImageEntity(id: 'img-1', authorId: 'U1'),
          ),
        ),
      );

      expect(find.byType(BeaconIdentityTile), findsOneWidget);
      expect(find.byType(TenturaIdentityTileFrame), findsOneWidget);
      expect(find.byType(BeaconImage), findsNothing);
    });

    testWidgets('FieldRequestNode renders identity tile for cover thumb', (
      tester,
    ) async {
      await _pumpNode(
        tester,
        FieldRequestNode(
          request: const ConstellationRequest(
            id: 'req-1',
            authorId: 'U1',
            title: 'Need tools',
            status: 0,
            coverThumb: ImageEntity(id: 'img-1', authorId: 'U1'),
          ),
        ),
      );

      expect(find.byType(BeaconIdentityTile), findsOneWidget);
      expect(find.byType(TenturaIdentityTileFrame), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
    });

    testWidgets('FieldRequestNode symbol cover uses capability glyph', (
      tester,
    ) async {
      await _pumpNode(
        tester,
        FieldRequestNode(
          request: const ConstellationRequest(
            id: 'req-1',
            authorId: 'U1',
            title: 'Need tools',
            status: 0,
            needs: ['transport'],
            primaryNeedSlug: 'transport',
            coverSource: BeaconCoverSource.symbol,
            coverThumb: ImageEntity(id: 'img-stale', authorId: 'U1'),
          ),
        ),
      );

      expect(find.byType(TenturaCapabilityGlyph), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
