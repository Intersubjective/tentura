@Tags(['repo-files'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_identity.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_title.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_anchors_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_requests_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_targeted_read_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_request_identity.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_lens_panel.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

const _title = 'Нужна помощь';
const _loadedAt = '2026-11-08T12:00:00.000Z';
const _gallery = ImageEntity(
  id: 'selected-gallery-cover',
  authorId: 'ego',
  blurHash: 'gallery-hash',
  height: 64,
  width: 96,
);
const _firstGalleryImage = ImageEntity(
  id: 'first-gallery-image',
  authorId: 'ego',
);
const _thumb = ImageEntity(
  id: 'cropped-cover',
  authorId: 'ego',
  blurHash: 'thumb-hash',
  height: 48,
  width: 48,
);

Map<String, dynamic> _wireImage(ImageEntity image) => {
  '__typename': 'v2_image',
  'id': image.id,
  'hash': image.blurHash,
  'height': image.height,
  'width': image.width,
  'author_id': image.authorId,
  'created_at': _loadedAt,
};

Map<String, dynamic> _wireRequest(
  String id, {
  BeaconCoverSource source = BeaconCoverSource.photo,
  ImageEntity? thumb,
  String? primaryNeedSlug,
}) => {
  '__typename': 'v2_ConstellationRequest',
  'id': id,
  'pinState': null,
  'authorId': 'ego',
  'title': _title,
  'status': 0,
  'needs': [?primaryNeedSlug],
  'primaryNeedSlug': primaryNeedSlug,
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
  'coverSource': source.wireValue,
  'coverThumb': thumb == null ? null : _wireImage(thumb),
  'coverImage': _wireImage(_gallery),
  'has_unread': false,
};

Map<String, dynamic> _fieldResponse(List<Map<String, dynamic>> requests) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': _loadedAt,
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': <String>[],
    'peers': <dynamic>[],
    'edges': <dynamic>[],
    'requests': requests,
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '0',
      'anchors': <dynamic>[],
      'pinnedPeers': <dynamic>[],
      'pinnedRequests': [_wireRequest('pinned')],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <String>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

// Build each JSON response from the actual HTTP selection, expanding the
// fragments sent by Ferry. A stored gallery cover is sent only if selected.
Map<String, dynamic> _selectResponse(String query, Map<String, dynamic> data) {
  final document = parseString(query);
  final operation = document.definitions
      .whereType<OperationDefinitionNode>()
      .single;
  final fragments = {
    for (final fragment
        in document.definitions.whereType<FragmentDefinitionNode>())
      fragment.name.value: fragment.selectionSet,
  };

  Iterable<FieldNode> fields(SelectionSetNode set) sync* {
    for (final selection in set.selections) {
      switch (selection) {
        case FieldNode():
          yield selection;
        case FragmentSpreadNode():
          yield* fields(fragments[selection.name.value]!);
        case InlineFragmentNode():
          yield* fields(selection.selectionSet);
      }
    }
  }

  Object? project(Object? value, SelectionSetNode? set) {
    if (value == null || set == null) return value;
    if (value is List<Object?>) {
      return value.map((item) => project(item, set)).toList();
    }
    final object = value as Map<String, dynamic>;
    return {
      for (final field in fields(set))
        if (object.containsKey((field.alias ?? field.name).value))
          (field.alias ?? field.name).value: project(
            object[(field.alias ?? field.name).value],
            field.selectionSet,
          ),
    };
  }

  return project(data, operation.selectionSet)! as Map<String, dynamic>;
}

Map<String, dynamic> _headerResponse(Map<String, dynamic> request) {
  Map<String, dynamic> image(ImageEntity value) => {
    ..._wireImage(value),
    '__typename': 'image',
  };

  const emptyOffers = {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  };
  final thumb = request['coverThumb'] == null ? null : _thumb;
  return {
    '__typename': 'query_root',
    'beacon_by_pk': {
      '__typename': 'beacon',
      'id': request['id'],
      'title': request['title'],
      'description': '',
      'status': request['status'],
      'kind': 0,
      'forward_policy': 1,
      'created_at': _loadedAt,
      'updated_at': _loadedAt,
      'is_discoverable': true,
      'can_read_content': true,
      'needs': (request['needs'] as List<String>).join(','),
      'tags': '',
      'primary_need_slug': request['primaryNeedSlug'],
      'cover_source': request['coverSource'],
      'cover_image_id': _gallery.id,
      'cover_thumb_image_id': thumb?.id,
      'cover_thumb_image': thumb == null ? null : image(thumb),
      'beacon_images': [
        for (final value in [_firstGalleryImage, _gallery])
          {'__typename': 'beacon_image', 'image': image(value)},
      ],
      'author': {
        '__typename': 'user',
        'id': request['authorId'],
        'display_name': 'Имя автора',
        'description': '',
      },
      'help_offers_aggregate': emptyOffers,
      'unanswered_help_offers': emptyOffers,
      'admitted_helpers_aggregate': {
        '__typename': 'beacon_admitted_helper_aggregate',
        'aggregate': null,
      },
      'active_help_offers': <Object>[],
      'participant_help_offers': <Object>[],
      'admitted_helpers': <Object>[],
      'post_draft_attachments': <Object>[],
    },
  };
}

Future<Map<String, Beacon>> _fetchHeaderBeacons(
  List<Map<String, dynamic>> requests,
) async {
  final sent = <WireSent>[];
  final beacons = <String, Beacon>{};
  final realtime = TestRealtimeSyncPort();
  try {
    await withRemoteWire(
      const {},
      sent,
      (remote) async {
        final repository = BeaconRepository(remote, realtime);
        try {
          for (final request in requests) {
            final id = request['id'] as String;
            beacons[id] = await repository.fetchBeaconById(id);
          }
        } finally {
          await repository.dispose();
        }
      },
      responseFor: (call) async => _headerResponse(
        requests.singleWhere(
          (request) => request['id'] == call.variables['id'],
        ),
      ),
      selectResponse: _selectResponse,
    );
  } finally {
    await realtime.dispose();
  }
  expect(
    sent.map((call) => call.operationName),
    everyElement('BeaconFetchById'),
  );
  return beacons;
}

Future<ConstellationField> _fetchField(
  List<Map<String, dynamic>> requests, {
  ConstellationProjection projection = ConstellationProjection.full,
  void Function(Map<String, dynamic>)? observeResponse,
}) async {
  final operation = projection == ConstellationProjection.anchors
      ? 'ConstellationAnchorsFetch'
      : 'ConstellationFieldFetch';
  late ConstellationField field;
  final sent = <WireSent>[];
  await withRemoteWire(
    {operation: _fieldResponse(requests)},
    sent,
    (remote) async {
      field = await ConstellationRepository(
        remote,
      ).fetch(projection: projection);
    },
    selectResponse: (query, data) {
      final response = _selectResponse(query, data);
      observeResponse?.call(response);
      return response;
    },
  );
  expect(sent.single.operationName, operation);
  return field;
}

SelectionSetNode? _selectionsAt(DocumentNode doc, List<String> path) {
  SelectionSetNode? selections = doc.definitions
      .whereType<OperationDefinitionNode>()
      .single
      .selectionSet;
  for (final name in path) {
    final fields = selections?.selections.whereType<FieldNode>();
    selections = fields
        ?.where((field) => field.name.value == name)
        .firstOrNull
        ?.selectionSet;
  }
  return selections;
}

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(body: Center(child: child)),
  ),
);

void _expectIdentityPhoto(
  WidgetTester tester,
  Finder tile,
  ImageEntity image,
) {
  expect(tile, findsOneWidget);
  expect(tester.takeException(), isNull);
  final url = Beacon.empty.urlForImage(image);
  final photo = find.descendant(
    of: tile,
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      final original = provider is ResizeImage
          ? provider.imageProvider
          : provider;
      return original is NetworkImage && original.url == url;
    }, description: 'identity photo at $url'),
  );
  expect(
    photo,
    findsOneWidget,
    reason: 'The Request displays its selected identity photo',
  );
  expect(
    find.descendant(
      of: tile,
      matching: find.byType(BeaconIdentityNeutralGlyph),
    ),
    findsNothing,
  );
}

void main() {
  final documents = {
    'constellation_field_fetch': (
      'a Field load for regular and pinned Requests',
      GConstellationFieldFetchReq((builder) {
        builder.vars
          ..showClosed = false
          ..participatedOnly = false
          ..projection = Gv2_ConstellationProjection.FULL;
      }).operation.document,
      [
        ['constellationField', 'requests'],
        ['constellationField', 'anchorProjection', 'pinnedRequests'],
      ],
    ),
    'constellation_anchors_fetch': (
      'a placement refresh for pinned Requests',
      GConstellationAnchorsFetchReq((builder) {
        builder.vars
          ..showClosed = false
          ..participatedOnly = false;
      }).operation.document,
      [
        ['constellationField', 'anchorProjection', 'pinnedRequests'],
      ],
    ),
    'constellation_field_requests_fetch': (
      'a targeted Request refresh',
      GConstellationFieldRequestsFetchReq((builder) {
        builder.vars
          ..ids.add('request')
          ..showClosed = false
          ..participatedOnly = false;
      }).operation.document,
      [
        ['constellationFieldRequests'],
      ],
    ),
  };

  for (final entry in documents.entries) {
    final (read, generated, paths) = entry.value;
    test(
      'fetches the selected gallery image for $read',
      () {
        final source = parseString(
          File(
            'lib/features/constellation/data/gql/${entry.key}.graphql',
          ).readAsStringSync(),
        );
        final missing = [
          for (final (kind, document) in [
            ('source', source),
            ('Ferry', generated),
          ])
            for (final path in paths)
              if (!(_selectionsAt(document, [
                    ...path,
                    'coverImage',
                  ])?.selections.whereType<FragmentSpreadNode>().any(
                    (fragment) => fragment.name.value == 'ImageModelV2',
                  ) ??
                  false))
                '$kind: ${path.join('.')}.coverImage { ...ImageModelV2 }',
        ];
        expect(
          missing,
          isEmpty,
          reason: 'Each operation must request the photo',
        );
      },
    );
  }

  test(
    'a Field fetch transports the selected gallery image and its metadata',
    () async {
      late Map<String, dynamic> response;
      final field = await _fetchField(
        [_wireRequest('gallery')],
        observeResponse: (data) => response = data,
      );
      expect(field.requests.single.id, 'gallery');
      final payload = response['constellationField'] as Map<String, dynamic>;
      final rows = payload['requests'] as List<Object?>;
      final row = rows.single! as Map<String, dynamic>;
      expect(row['id'], 'gallery');
      expect(row['coverThumb'], isNull);
      expect(row['coverImage'], {
        '__typename': 'v2_image',
        'id': _gallery.id,
        'hash': _gallery.blurHash,
        'height': _gallery.height,
        'width': _gallery.width,
        'author_id': _gallery.authorId,
        'created_at': _loadedAt,
      });
    },
  );

  testWidgets(
    'Field Request identities match the rendered header for gallery, crop and symbol covers',
    (tester) async {
      await usePhoneSurface(tester);
      final requests = [
        _wireRequest('gallery'),
        _wireRequest('crop', thumb: _thumb),
        _wireRequest(
          'symbol',
          source: BeaconCoverSource.symbol,
          primaryNeedSlug: 'transport',
        ),
      ];
      final loaded = await tester.runAsync(() async {
        final field = await _fetchField(requests);
        final headers = await _fetchHeaderBeacons(requests);
        return (field, headers);
      });
      final (field, headers) = loaded!;
      expect(field.requests.map((request) => request.id), [
        'gallery',
        'crop',
        'symbol',
      ]);

      final expected = <String, BeaconIdentity>{};
      for (final entry in headers.entries) {
        await tester.pumpWidget(
          _host(
            BeaconViewAppBarTitle(
              beacon: entry.value,
              phaseStatus: const BeaconPhaseStatusPresentation(
                slot1: 'Открыт',
                slot1Tone: TenturaTone.neutral,
              ),
              l10n: lookupL10n(const Locale('ru')),
              showStatus: false,
            ),
          ),
        );
        final tile = find.descendant(
          of: find.byType(BeaconViewAppBarTitle),
          matching: find.byType(BeaconIdentityTile),
        );
        final identity = tester
            .widget<BeaconIdentityTile>(tile)
            .beacon
            .identity;
        expected[entry.key] = identity;
        switch (entry.key) {
          case 'gallery':
            _expectIdentityPhoto(tester, tile, _gallery);
          case 'crop':
            _expectIdentityPhoto(tester, tile, _thumb);
          case 'symbol':
            final glyph = find.descendant(
              of: tile,
              matching: find.byType(TenturaCapabilityGlyph),
            );
            expect(
              tester.widget<TenturaCapabilityGlyph>(glyph).tag,
              CapabilityTag.transport,
            );
            expect(
              find.descendant(of: tile, matching: find.byType(Image)),
              findsNothing,
            );
        }
      }

      expect(expected, {
        'gallery': const BeaconIdentityPhoto(_gallery),
        'crop': const BeaconIdentityPhoto(_thumb),
        'symbol': const BeaconIdentitySymbol(CapabilityTag.transport),
      });
      expect({
        for (final request in field.requests)
          request.id: constellationRequestAsIdentityBeacon(request).identity,
      }, expected);
    },
  );

  test(
    'pinned and targeted Field reads preserve the gallery photo without a thumb',
    () async {
      final field = await _fetchField([_wireRequest('ordinary')]);
      final pinned = field.resolvedAnchorProjection.pinnedRequests.single;
      final sent = <WireSent>[];
      late ConstellationRequest targeted;
      await withRemoteWire(
        {
          'ConstellationFieldRequestsFetch': {
            '__typename': 'query_root',
            'constellationFieldRequests': [_wireRequest('targeted')],
          },
        },
        sent,
        (remote) async {
          final requests = await ConstellationTargetedReadRepository(
            remote,
          ).fetchRequests({'targeted'});
          targeted = requests.single;
        },
        selectResponse: _selectResponse,
      );
      expect(sent.single.operationName, 'ConstellationFieldRequestsFetch');
      expect([pinned.id, targeted.id], ['pinned', 'targeted']);
      expect([pinned.coverThumb, targeted.coverThumb], [null, null]);
      expect(
        [pinned, targeted].map(
          (request) => constellationRequestAsIdentityBeacon(request).identity,
        ),
        const [BeaconIdentityPhoto(_gallery), BeaconIdentityPhoto(_gallery)],
      );
    },
  );

  test(
    'refreshing placements keeps the gallery cover on a pinned Request',
    () async {
      final field = await _fetchField(
        [],
        projection: ConstellationProjection.anchors,
      );
      final request = field.resolvedAnchorProjection.pinnedRequests.single;
      expect(request.id, 'pinned');
      expect(request.coverThumb, isNull);
      expect(
        constellationRequestAsIdentityBeacon(request).identity,
        const BeaconIdentityPhoto(_gallery),
      );
    },
  );

  for (final (surface, content)
      in <(String, Widget Function(ConstellationRequest))>[
        (
          'identity tile',
          (request) => BeaconIdentityTile(
            beacon: constellationRequestAsIdentityBeacon(request),
          ),
        ),
        (
          'Field node',
          (request) => GraphNodeWidget(
            nodeDetails: FieldBeaconNode(request: request),
          ),
        ),
        (
          'tag-lens picker row',
          (request) => Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(
                showConstellationTagLensRequestPicker(context, [request]),
              ),
              child: const Text('Выбрать'),
            ),
          ),
        ),
      ]) {
    testWidgets(
      'the $surface displays the selected gallery cover on a Russian phone',
      (tester) async {
        await usePhoneSurface(tester);
        final field = await tester.runAsync(
          () => _fetchField([
            _wireRequest('gallery'),
          ]).timeout(const Duration(seconds: 15)),
        );
        final request = field!.requests.single;
        expect(request.coverThumb, isNull);

        await tester.pumpWidget(_host(content(request)));
        var tile = find.byType(BeaconIdentityTile);
        if (surface == 'tag-lens picker row') {
          await tester.tap(find.text('Выбрать'));
          await tester.pump();
          final l10n = lookupL10n(const Locale('ru'));
          expect(
            find.text(l10n.constellationTagLensPickRequest),
            findsOneWidget,
          );
          final title = find.text(_title);
          expect(title, findsOneWidget);
          tile = find.descendant(
            of: find.ancestor(of: title, matching: find.byType(ListTile)),
            matching: tile,
          );
        }

        _expectIdentityPhoto(tester, tile, _gallery);
      },
    );
  }
}
