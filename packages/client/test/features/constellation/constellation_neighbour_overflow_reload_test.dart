@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_control.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_layer.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _tag = PersonTag(
  id: 'qa-magnet',
  name: 'QA Magnet',
  glyph: 'Q',
  color: 0,
  ord: 0,
);

// Alice has +28 on desktop and +30 on a phone; Bob has +3 on desktop.
// The neighbouring cluster is displaced like the clipped control in the report:
// 25 logical pixels right and 12 above at the default camera scale.
ConstellationField _field() {
  final revision = ConstellationAnchorRevision(BigInt.one);
  final loadedAt = DateTime.utc(2026, 10, 29);
  return ConstellationField(
    loadedAt: loadedAt,
    context: '',
    peers: const [ConstellationPerson(id: 'bob', displayName: 'Bob')],
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'bob', tier: 1),
    ],
    directContactIds: const ['bob'],
    requests: [
      for (final (author, count) in [('ego', 31), ('bob', 6)])
        for (var i = 0; i < count; i++)
          ConstellationRequest(
            id: '$author-$i',
            authorId: author,
            title: 'Request $i by $author',
            status: 0,
            isMine: author == 'ego',
          ),
    ],
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person('bob'),
          position: const ConstellationAnchorPosition(
            xUnits: 25 / 170,
            yUnits: -12 / 170,
            coordinateSpaceVersion: 1,
          ),
          revision: revision,
          placedAt: loadedAt,
        ),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _SavedMagnets implements ConstellationTagMagnetRepositoryPort {
  _SavedMagnets(this.enabled);
  bool enabled;
  Completer<void>? readGate;

  @override
  Future<List<ConstellationTagMagnet>> list() async {
    await readGate?.future;
    return [
      if (enabled)
        const ConstellationTagMagnet(
          tagId: 'qa-magnet',
          xUnits: 0,
          yUnits: 0.7,
          revision: 1,
        ),
    ];
  }

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) => throw StateError('Cold builds only read saved magnets');

  @override
  Future<void> remove({
    required String tagId,
    required String clientOpId,
  }) async {
    enabled = false;
  }
}

void main() {
  group('Neighbouring Field overflow controls across cold builds', () {
    for (final size in [const Size(375, 667), const Size(1280, 900)]) {
      for (final magnet in [false, true]) {
        testWidgets(
          '${size.width.toInt()}px with magnet ${magnet ? 'on' : 'off'} builds one separate stable chip per author',
          (tester) async {
            final rig = await PeopleTagsTestRig.create(
              FakePeopleTagsRepository(
                tagList: const [_tag],
                memberList: const [
                  PersonTagMembers(tagId: 'qa-magnet', personIds: ['bob']),
                ],
              ),
            );
            GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
            addTearDown(() async {
              await GetIt.I.unregister<PeopleTagsCase>();
              await rig.dispose();
            });
            final realtime = buildTestRealtimeSync();
            addTearDown(realtime.port.dispose);
            final repository = _SavedMagnets(magnet);
            final snapshots = <Map<String, Rect>>[];
            final failures = <String>[];
            for (var coldBuild = 0; coldBuild < 2; coldBuild++) {
              repository
                ..enabled = magnet
                ..readGate = magnet ? Completer<void>() : null;
              final cubit = ConstellationCubit(
                case_: constellationCaseForField(_field()),
                viewer: const Profile(id: 'ego', displayName: 'Alice'),
                ownTagIdsOf: rig.peopleTags.tagsOfPerson,
                tagMagnetCase: ConstellationTagMagnetCase(
                  repository,
                  realtime.case_,
                  env: const Env(),
                  logger: Logger('neighbour overflow reload'),
                ),
              );
              addTearDown(() async {
                if (!cubit.isClosed) await cubit.close();
              });
              await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
              await pumpConstellationBody(
                tester,
                cubit,
                size: size,
                locale: const Locale('en'),
              );
              repository.readGate?.complete();
              for (var frame = 0; frame < 90; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                final owner = find.byKey(
                  const Key('constellation.overflow.ego'),
                );
                final neighbour = find.byKey(
                  const Key('constellation.overflow.bob'),
                );
                expect(owner, findsOneWidget);
                expect(neighbour, findsOneWidget);
                final ownerRect = tester.getRect(owner);
                final neighbourRect = tester.getRect(neighbour);
                if (ownerRect.overlaps(neighbourRect)) {
                  failures.add(
                    'Cold build $coldBuild frame $frame: Alice $ownerRect overlaps Bob $neighbourRect',
                  );
                }
              }
              await tester.pumpAndSettle();
              expect(
                cubit.tagMagnets.keys,
                magnet ? contains('qa-magnet') : isEmpty,
              );
              final rects = <String, Rect>{};
              expect(find.byType(ConstellationOverflowGroup), findsNWidgets(2));
              for (final author in ['ego', 'bob']) {
                final group = find.byWidgetPredicate(
                  (w) =>
                      w is ConstellationOverflowGroup && w.authorId == author,
                );
                expect(group, findsOneWidget);
                final control = tester.widget<ConstellationOverflowGroup>(
                  group,
                );
                expect(
                  control.hiddenCount,
                  author == 'ego'
                      ? (size.width < 600 ? 30 : 28)
                      : (size.width < 600 ? 5 : 3),
                  reason:
                      'the fixture keeps a large owner overflow beside a small neighbour overflow',
                );
                final chip = find.byKey(Key('constellation.overflow.$author'));
                expect(chip, findsOneWidget);
                expect(
                  find.descendant(
                    of: chip,
                    matching: find.text('+${control.hiddenCount} more'),
                  ),
                  findsOneWidget,
                );
                rects[author] = tester.getRect(chip);
                expect(rects[author]!.size.isEmpty, isFalse);
              }
              if (rects['ego']!.overlaps(rects['bob']!)) {
                failures.add(
                  'Cold build $coldBuild: Alice ${rects['ego']} overlaps Bob ${rects['bob']}',
                );
              }
              snapshots.add(rects);
              final magnetControl = find.descendant(
                of: find.byType(ConstellationTagMagnetLayer),
                matching: find.byType(ConstellationTagMagnetControl),
              );
              expect(magnetControl, magnet ? findsOneWidget : findsNothing);
              if (magnet) {
                await tester.tap(
                  find.descendant(
                    of: magnetControl,
                    matching: find.byType(IconButton),
                  ),
                );
                await tester.pumpAndSettle();
                await tester.tap(find.text('Remove'));
                for (var frame = 0; frame < 90; frame++) {
                  await tester.pump(const Duration(milliseconds: 16));
                  final owner = find.byKey(
                    const Key('constellation.overflow.ego'),
                  );
                  final neighbour = find.byKey(
                    const Key('constellation.overflow.bob'),
                  );
                  expect(owner, findsOneWidget);
                  expect(neighbour, findsOneWidget);
                  final ownerRect = tester.getRect(owner);
                  final neighbourRect = tester.getRect(neighbour);
                  if (ownerRect.overlaps(neighbourRect)) {
                    failures.add(
                      'Cold build $coldBuild removal frame $frame: Alice $ownerRect overlaps Bob $neighbourRect',
                    );
                  }
                }
                expect(magnetControl, findsNothing);
                expect(repository.enabled, isFalse);
                expect(
                  find.byType(ConstellationOverflowGroup),
                  findsNWidgets(2),
                );
              }
              // Destroy the body and cubit, including their camera and overlay caches.
              await tester.pumpWidget(const SizedBox.shrink());
              await cubit.close();
            }
            for (final author in ['ego', 'bob']) {
              if (snapshots[0][author] != snapshots[1][author]) {
                failures.add(
                  '$author moves across cold builds: ${snapshots[0][author]} -> ${snapshots[1][author]}',
                );
              }
            }
            expect(
              failures,
              isEmpty,
              reason:
                  'Overflow chips must remain distinct and repeatable after reload',
            );
          },
        );
      }
    }
  });
}
