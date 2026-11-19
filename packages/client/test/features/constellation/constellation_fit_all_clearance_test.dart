@TestOn('vm')
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/features/home/ui/widget/home_nav_destinations.dart';
import 'package:tentura/features/home/ui/widget/home_rail_layout.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/home_tab.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'bob', displayName: 'Боб');
const _requestAuthor = 'lena';
const _requestId = 'request-lena';
const _postId = 'post-bob';
const _arrange = Key('constellation.camera.arrange');

typedef _Anchors = Map<String, (double, double)>;

const _horizontal = <String, (double, double)>{
  'west': (-10, 0),
  'east': (10, 0),
};
const _vertical = <String, (double, double)>{
  'north': (0, -10),
  'south': (0, 10),
};

Map<String, dynamic> _peer(String id) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'displayName': id == _viewer.id ? _viewer.displayName : id,
  'contactOnly': false,
  'pinState': null,
  'handle': null,
  'image': null,
  'isNew': false,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'visible': true,
  'helpOfferCount': 0,
  'coverSource': 0,
  'coverThumb': null,
};

Map<String, dynamic> _fieldResponse(_Anchors contacts) {
  final directContacts = {_requestAuthor: (1.0, 1.0), ...contacts};
  final anchors = {_viewer.id: (0.0, 0.0), ...directContacts};
  final now = DateTime.now().toUtc();
  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': now.toIso8601String(),
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': directContacts.keys.toList(),
      'peers': anchors.keys.map(_peer).toList(),
      'edges': [
        for (final id in directContacts.keys)
          {
            '__typename': 'v2_ConstellationEdge',
            'src': _viewer.id,
            'dst': id,
            'tier': 1,
          },
      ],
      'requests': [
        {
          '__typename': 'v2_ConstellationRequest',
          'id': _requestId,
          'pinState': null,
          'authorId': _requestAuthor,
          'title': 'Нужна лестница',
          'status': 0,
          'needs': <String>[],
          'primaryNeedSlug': null,
          'startAt': null,
          'endAt': null,
          'lastActivityAt': now.toIso8601String(),
          'addressLabel': null,
          'hasCoordinates': false,
          'isMine': false,
          'viewerHasActiveHelpOffer': false,
          'viewerIsRoomParticipant': true,
          'viewerHasForwardEdge': false,
          'forwardedById': null,
          'forwardedByName': null,
          'parentBeaconId': null,
          'helpOfferCount': 0,
          'coverSource': 0,
          'coverThumb': null,
          'has_unread': false,
        },
      ],
      'posts': [
        {
          '__typename': 'v2_ConstellationPost',
          'id': _postId,
          'authorId': _viewer.id,
          'lastActivityAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(days: 2)).toIso8601String(),
          'status': 0,
          'rootExcerpt': 'Встреча в субботу',
          'isPinned': false,
          'hiddenReachCount': 0,
          'has_unread': false,
        },
      ],
      'memberWebs': <dynamic>[],
      'anchorProjection': {
        '__typename': 'v2_ConstellationAnchorProjection',
        'revision': '1',
        'anchors': [
          for (final MapEntry(:key, :value) in anchors.entries)
            {
              '__typename': 'v2_ConstellationAnchor',
              'targetKind': 'PERSON',
              'targetId': key,
              'xUnits': value.$1,
              'yUnits': value.$2,
              'coordinateSpaceVersion': 1,
              'revision': '1',
              'placedAt': now.toIso8601String(),
            },
        ],
        'pinnedPeers': directContacts.keys.map(_peer).toList(),
        'pinnedRequests': <dynamic>[],
        'supportPeers': <dynamic>[],
        'supportEdges': <dynamic>[],
        'serverFilteredBeaconIds': <dynamic>[],
        'serverFilteredBeaconCount': 0,
      },
    },
  };
}

Future<void> _settleCamera(WidgetTester tester) async {
  // The Field can animate chrome continuously. Pump a bounded set of frames.
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Widget _withPhoneNavigation(Widget body) => Builder(
  builder: (context) => HomeRailLayout.compact(
    bottomBar: HomeBottomNavigationBar(
      selectedIndex: HomeTabSpec.destinationIndexFor(
        HomeTabSpec.forTab(HomeTab.constellation).index,
      ),
      onDestinationSelected: (_) {},
      destinations: [
        for (final destination in homeNavDestinations(
          L10n.of(context)!,
          badged: false,
        ))
          HomeNavDestination(
            icon: destination.icon,
            selectedIcon: destination.selectedIcon,
            label: destination.label,
          ),
      ],
    ),
    child: body,
  ),
);

void _clearanceTest(
  String description,
  _Anchors contacts, {
  required bool phone,
}) {
  testWidgets(description, (tester) async {
    if (phone) await usePhoneSurface(tester);
    await withRemoteWire(
      {'ConstellationFieldFetch': _fieldResponse(contacts)},
      [],
      (remote) async {
        final store = ConstellationStoreFixture(
          ConstellationRepository(remote),
          accountId: _viewer.id,
        );
        final cubit = store.createCubit(viewer: _viewer);
        try {
          final loaded = cubit.stream.firstWhere(
            (s) => s.status is StateIsSuccess,
          );
          unawaited(cubit.load());
          await tester.runAsync(
            () => loaded.timeout(const Duration(seconds: 10)),
          );
          await pumpConstellationBody(
            tester,
            cubit,
            size: phone ? kPhoneSurface : const Size(1280, 800),
            wrapBody: phone ? _withPhoneNavigation : null,
            locale: Locale(phone ? 'ru' : 'en'),
            arrangeV2Enabled: true,
          );
          await _settleCamera(tester);

          final fit = find.byKey(TestIds.key(TestIds.constellationFitAll));
          final centre = find.byKey(
            TestIds.key(TestIds.constellationCenterOnMe),
          );
          final arrange = find.byKey(_arrange);
          expect(
            tester.widget<IconButton>(fit).tooltip,
            phone ? 'Показать всё поле' : 'Show whole field',
          );

          // Start at close zoom so a fit-all tap must change the camera.
          expect(centre.hitTestable(), findsOneWidget);
          await tester.tap(centre);
          await _settleCamera(tester);
          final graph = cubit.graphController;
          final startScale = graph.cameraScale;

          expect(fit.hitTestable(), findsOneWidget);
          await tester.tap(fit);
          await _settleCamera(tester);

          expect(tester.takeException(), isNull);
          expect(graph.cameraScale, lessThan(startScale));
          if (phone && contacts.containsKey('west')) {
            expect(
              graph.cameraScale,
              lessThan(kConstellationDistrictDetailScale),
            );
          }

          final canvas = find.byType(GraphView<NodeDetails, EdgeDetails>);
          final origin = tester.getTopLeft(canvas);
          final buttonRects = {
            for (final button in [fit, centre, arrange])
              tester.widget<IconButton>(button).tooltip!: tester
                  .getRect(button)
                  .shift(-origin),
          };
          final columnLeft = buttonRects.values
              .map((rect) => rect.left)
              .reduce(math.min);
          final viewport = Offset.zero & graph.viewportSize!;
          final chrome = cubit.fieldCameraViewportSnapshotForTest;
          final nav = phone
              ? tester
                    .getRect(find.byType(HomeBottomNavigationBar))
                    .shift(-origin)
              : null;
          if (nav != null) expect(nav.height, greaterThan(0));
          final chromeBottom = viewport.bottom - chrome.bottom;
          final visibleArea = Rect.fromLTRB(
            viewport.left + chrome.left,
            viewport.top + chrome.top,
            columnLeft,
            nav == null ? chromeBottom : math.min(chromeBottom, nav.top),
          );

          final snapshot = graph.renderSnapshot;
          final viewer = snapshot.resolvePosition('fp:${_viewer.id}')!;
          for (final MapEntry(:key, :value) in contacts.entries) {
            final contact = snapshot.resolvePosition('fp:$key')!;
            if (value.$1 != 0) {
              expect((contact.x - viewer.x) * value.$1.sign, greaterThan(1000));
            }
            if (value.$2 != 0) {
              expect((contact.y - viewer.y) * value.$2.sign, greaterThan(1000));
            }
          }
          final checkedIds = <String>{};
          final violations = <String>[];
          for (final MapEntry(key: id, value: node)
              in snapshot.topology.nodesById.entries) {
            final payload = node.payload;
            if (payload is! FieldPersonNode && payload is! FieldBeaconNode) {
              continue;
            }
            checkedIds.add(payload.id);
            final position = snapshot.resolvePosition(id);
            expect(position, isNotNull, reason: '$id has a laid-out body');
            final scene = Rect.fromCenter(
              center: Offset(position!.x, position.y),
              width: node.size.width,
              height: node.size.height,
            );
            final body = Rect.fromPoints(
              graph.sceneToViewportLocal(scene.topLeft),
              graph.sceneToViewportLocal(scene.bottomRight),
            );
            final radius = node.size.width / 2;
            final gaps = {
              'left': body.left - visibleArea.left,
              'right of body to button column': visibleArea.right - body.right,
              'top': body.top - visibleArea.top,
              'bottom above chrome': visibleArea.bottom - body.bottom,
            };
            for (final MapEntry(key: side, value: gap) in gaps.entries) {
              if (gap < radius - 0.01) {
                violations.add(
                  '$id $side clearance is ${gap.toStringAsFixed(2)} px, needs $radius px',
                );
              }
            }
            for (final MapEntry(key: name, value: rect)
                in buttonRects.entries) {
              if (body.overlaps(rect)) violations.add('$id overlaps "$name"');
            }
          }
          expect(
            checkedIds,
            containsAll([
              _viewer.id,
              ...contacts.keys,
              _requestAuthor,
              _requestId,
              _postId,
            ]),
          );
          expect(
            violations,
            isEmpty,
            reason:
                'Body clearance after fitting at scale ${graph.cameraScale}',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await cubit.close();
          await tester.pump();
        }
      },
    );
  });
}

void main() {
  group(
    'Show whole field keeps node bodies clear of the viewport edges and controls',
    () {
      _clearanceTest(
        'phone leaves room at the left edge and before the map buttons',
        _horizontal,
        phone: true,
      );
      _clearanceTest(
        'phone leaves room below the top and above the bottom chrome',
        _vertical,
        phone: true,
      );
      _clearanceTest('phone leaves room on all four sides for one field', {
        ..._horizontal,
        ..._vertical,
      }, phone: true);
      _clearanceTest(
        'desktop leaves room around contacts spread left and right',
        _horizontal,
        phone: false,
      );
      _clearanceTest(
        'desktop leaves room around contacts spread up and down',
        _vertical,
        phone: false,
      );
    },
  );
}
