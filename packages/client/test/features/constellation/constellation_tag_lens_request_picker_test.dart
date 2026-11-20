import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_identity.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/constellation_request_identity.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_lens_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import '../../support/phone_surface.dart';

const _longRuTitle =
    'Очень длинное название открытого запроса для пересылки из теговой линзы, '
    'которое не должно выходить за границы строки на узком телефоне';

final _thumbBytes = ImageEntity(
  id: 'thumb-covered',
  authorId: 'ego',
  imageBytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwaDjwHwAFBAKAPJ4DgAAAAABJRU5ErkJggg==',
  ),
);

Future<void> _pumpPickerHost(
  WidgetTester tester, {
  required Locale locale,
  required void Function(BuildContext context) openPicker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => openPicker(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

ConstellationRequest _request({
  required String id,
  required String title,
  ImageEntity? coverThumb,
  BeaconCoverSource coverSource = BeaconCoverSource.photo,
  List<String> needs = const [],
  String? primaryNeedSlug,
}) => ConstellationRequest(
  id: id,
  authorId: 'ego',
  title: title,
  status: 0,
  isMine: true,
  coverThumb: coverThumb,
  coverSource: coverSource,
  needs: needs,
  primaryNeedSlug: primaryNeedSlug,
);

void main() {
  group('tag lens forward-which-Request picker', () {
    testWidgets('RU 375×667: long titles with and without cover, no overflow', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final l10n = lookupL10n(const Locale('ru'));

      final requests = [
        _request(id: 'r-neutral', title: _longRuTitle),
        _request(
          id: 'r-cover',
          title: 'Запрос с обложкой',
          coverThumb: _thumbBytes,
        ),
        _request(
          id: 'r-symbol',
          title: 'Запрос с символом',
          coverSource: BeaconCoverSource.symbol,
          needs: const ['transport'],
          primaryNeedSlug: 'transport',
        ),
      ];

      await _pumpPickerHost(
        tester,
        locale: const Locale('ru'),
        openPicker: (context) {
          unawaited(showConstellationTagLensRequestPicker(context, requests));
        },
      );

      final heading = find.text(l10n.constellationTagLensPickRequest);
      expect(heading, findsOneWidget);
      expect(find.byType(BeaconIdentityTile), findsNWidgets(3));
      for (final request in requests) {
        final title = find.text(request.title);
        expect(title, findsOneWidget);
        final row = find.ancestor(of: title, matching: find.byType(ListTile));
        final tile = find.descendant(
          of: row,
          matching: find.byType(BeaconIdentityTile),
        );
        expect(tester.widget<ListTile>(row).leading, same(tester.widget(tile)));
        expect(
          tester.getTopLeft(tile).dx,
          lessThan(tester.getTopLeft(title).dx),
        );
        expect(
          tester.getTopLeft(row).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(heading).dy),
        );
        expect(
          tester.getRect(title).right,
          lessThanOrEqualTo(kPhoneSurface.width),
        );

        final image = find.descendant(of: tile, matching: find.byType(Image));
        final neutral = find.descendant(
          of: tile,
          matching: find.byType(BeaconIdentityNeutralGlyph),
        );
        final symbol = find.descendant(
          of: tile,
          matching: find.byType(TenturaCapabilityGlyph),
        );
        expect(image, request.id == 'r-cover' ? findsOneWidget : findsNothing);
        expect(
          neutral,
          request.id == 'r-neutral' ? findsOneWidget : findsNothing,
        );
        expect(
          symbol,
          request.id == 'r-symbol' ? findsOneWidget : findsNothing,
        );
        if (request.id == 'r-neutral') {
          expect(
            find.descendant(
              of: neutral,
              matching: find.byIcon(Icons.campaign_outlined),
            ),
            findsOneWidget,
          );
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty picker shows the localized message', (tester) async {
      const locale = Locale('ru');
      await _pumpPickerHost(
        tester,
        locale: locale,
        openPicker: (context) {
          unawaited(showConstellationTagLensRequestPicker(context, const []));
        },
      );

      expect(
        find.text(lookupL10n(locale).constellationTagLensNoRequests),
        findsOneWidget,
      );
      expect(find.byType(BeaconIdentityTile), findsNothing);
    });

    testWidgets('tapping a row pops that Request', (tester) async {
      ConstellationRequest? picked;
      final requests = [
        _request(id: 'pick-me', title: 'Pick this one'),
        _request(id: 'other', title: 'Other'),
      ];

      await _pumpPickerHost(
        tester,
        locale: const Locale('en'),
        openPicker: (context) async {
          picked = await showConstellationTagLensRequestPicker(
            context,
            requests,
          );
        },
      );

      await tester.tap(find.text('Pick this one'));
      await tester.pumpAndSettle();

      expect(picked?.id, 'pick-me');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    test(
      'ConstellationFieldFetch wire maps coverThumb into picker identity',
      () {
        final wire = {
          '__typename': 'query_root',
          'constellationField': {
            '__typename': 'v2_ConstellationField',
            'loadedAt': '2026-11-08T12:00:00.000Z',
            'context': '',
            'peersCapped': false,
            'requestsCapped': false,
            'directContactIds': <String>[],
            'peers': <dynamic>[],
            'edges': <dynamic>[],
            'requests': [
              {
                '__typename': 'v2_ConstellationRequest',
                'id': 'req-wire',
                'pinState': null,
                'authorId': 'ego',
                'title': 'Wire-mapped',
                'status': 0,
                'needs': <String>[],
                'primaryNeedSlug': null,
                'startAt': null,
                'endAt': null,
                'lastActivityAt': null,
                'addressLabel': null,
                'hasCoordinates': false,
                'isMine': true,
                'viewerHasActiveHelpOffer': false,
                'viewerIsRoomParticipant': false,
                'viewerHasForwardEdge': false,
                'forwardedById': null,
                'forwardedByName': null,
                'parentBeaconId': null,
                'helpOfferCount': 0,
                'coverSource': 0,
                'coverThumb': {
                  '__typename': 'v2_image',
                  'id': 'img-wire',
                  'hash': 'hash-wire',
                  'height': 48,
                  'width': 48,
                  'author_id': 'ego',
                  'created_at': '2026-11-08T12:00:00.000Z',
                },
                'has_unread': false,
              },
            ],
            'posts': <dynamic>[],
            'memberWebs': <dynamic>[],
            'anchorProjection': {
              '__typename': 'v2_ConstellationAnchorProjection',
              'revision': '0',
              'anchors': <dynamic>[],
              'pinnedPeers': <dynamic>[],
              'pinnedRequests': <dynamic>[],
              'supportPeers': <dynamic>[],
              'supportEdges': <dynamic>[],
              'serverFilteredBeaconIds': <dynamic>[],
              'serverFilteredBeaconCount': 0,
            },
          },
        };

        final field = mapConstellationFieldFromFieldFetch(
          GConstellationFieldFetchData.fromJson(wire)!.constellationField,
        );
        final request = field.requests.single;
        expect(request.coverThumb?.id, 'img-wire');

        final identity = constellationRequestAsIdentityBeacon(request)
            .resolveIdentity(
              allowPhoto: true,
            );
        expect(identity, isA<BeaconIdentityPhoto>());
      },
    );
  });
}
