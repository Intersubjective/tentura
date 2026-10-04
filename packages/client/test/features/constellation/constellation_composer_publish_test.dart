// Sending from the graph composer: a Post is published once, then anchored at
// the normalised drop point under the current field generation; an anchor
// failure keeps the published Post and reports it; «Подробнее» hands the same
// draft id, recipients and per-recipient notes to the full form.

import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/port/post_publish_port.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _positions = <String, Offset>{
  'Ua': Offset(10, 0),
  'Ub': Offset(20, 0),
  'Uc': Offset(30, 0),
  'Ud': Offset(100, 0),
};

const _dropPoint = Offset(40, -25);

class _RecordingPostPublishPort implements PostPublishPort {
  final events = <String>[];

  @override
  Future<PostPublishResult> postPublish({
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    RoomPendingUpload? attachment,
  }) async {
    events.add('publish');
    return PostPublishResult(beaconId: beaconId, rootMessageId: 'root-1');
  }

  @override
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {}
}

class _RecordingAnchorRepository implements ConstellationAnchorRepositoryPort {
  _RecordingAnchorRepository(this.events);

  final List<String> events;
  Object? upsertError;
  final upserts =
      <
        ({
          ConstellationAnchorTarget target,
          ConstellationAnchorPosition position,
        })
      >[];

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    events.add('anchor');
    upserts.add((target: target, position: position));
    if (upsertError != null) throw upsertError!;
    final revision = ConstellationAnchorRevision(BigInt.two);
    return ConstellationAnchorUpsertResult(
      anchor: ConstellationAnchor(
        target: target,
        position: position,
        revision: revision,
        placedAt: DateTime.utc(2026, 10, 3),
      ),
      revision: revision,
    );
  }

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) => throw UnimplementedError();
}

class _EmptyFieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 3),
    context: '',
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.two),
      anchors: const [],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

void main() {
  late FakeBeaconWritePort write;
  late FakeUiEffectPort effects;
  late _RecordingPostPublishPort port;
  late _RecordingAnchorRepository anchorRepo;
  late ConstellationAnchorCase anchorCase;
  late ConstellationComposerCubit composer;
  late List<ForwardCubit> forwards;

  setUp(() {
    write = FakeBeaconWritePort();
    effects = FakeUiEffectPort();
    port = _RecordingPostPublishPort();
    forwards = [];
    anchorRepo = _RecordingAnchorRepository(port.events);
    anchorCase = ConstellationAnchorCase(
      _EmptyFieldRepository(),
      anchorRepo,
      buildTestRealtimeSync().case_,
      env: const Env.fromEnvironment(),
      logger: Logger('composer-publish-test'),
    )..activate(viewerAccountId: 'ego');
    composer = ConstellationComposerCubit(
      positions: _positions,
      eligible: _positions.keys.toSet(),
      createCubitFactory: (kind) => BeaconCreateCubit(
        kind: kind,
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        postPublishCase: PostPublishCase(port),
        effects: effects,
      ),
      forwardCubitFactory: (beaconId) {
        final cubit = ForwardCubit(
          beaconId: beaconId,
          embedded: true,
          effects: effects,
          debugSkipInitialLoad: true,
        );
        forwards.add(cubit);
        return cubit;
      },
    );
  });

  tearDown(() async {
    anchorCase.deactivate();
    await composer.close();
    for (final f in forwards) {
      await f.close();
    }
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> startPost() async {
    anchorCase.bindLoadGeneration(7);
    composer.start(BeaconKind.post, Offset.zero);
    composer.moveDraft(_dropPoint);
    await composer.contentChanged();
    await settle();
  }

  group('sending a Post from the composer', () {
    test('publishes once, then anchors at the normalised drop point', () async {
      await startPost();

      final outcome = await composer.sendPost(
        body: 'Кто в субботу на велопрогулку?',
        anchorCase: anchorCase,
        generation: 7,
      );

      expect(outcome.published, isTrue);
      expect(outcome.anchored, isTrue);
      expect(effects.emitted, isEmpty, reason: 'no snackbar on success');
      expect(port.events, ['publish', 'anchor']);
      final upsert = anchorRepo.upserts.single;
      expect(upsert.target, ConstellationAnchorTarget.beacon('server-beacon'));
      expect(
        upsert.position,
        constellationPointToV1Anchor(
          (x: _dropPoint.dx, y: _dropPoint.dy),
        ),
      );
    });

    test(
      'keeps the Post and reports the failure when the anchor write fails',
      () async {
        await startPost();
        anchorRepo.upsertError = StateError('network');

        final outcome = await composer.sendPost(
          body: 'Кто в субботу на велопрогулку?',
          anchorCase: anchorCase,
          generation: 7,
        );

        expect(port.events, ['publish', 'anchor']);
        expect(outcome.published, isTrue);
        expect(outcome.anchored, isFalse);
        expect(outcome.beaconId, 'server-beacon');
        expect(
          write.deletedIds,
          isEmpty,
          reason: 'the Post is not rolled back',
        );
        expect(
          effects.emitted.whereType<ShowError>().length +
              effects.emitted.whereType<ShowMessage>().length,
          1,
          reason: 'the failure is shown once as a snackbar',
        );
      },
    );

    test('does not anchor when nothing was published', () async {
      await startPost();

      final outcome = await composer.sendPost(
        body: '   ',
        anchorCase: anchorCase,
        generation: 7,
      );

      expect(outcome.published, isFalse);
      expect(anchorRepo.upserts, isEmpty);
      expect(port.events, isEmpty);
    });
  });

  group('«Подробнее» hand-off to the full form', () {
    test('carries the draft id, recipients and notes', () async {
      composer.start(BeaconKind.request, Offset.zero);
      await composer.contentChanged();
      await settle();
      composer.forwardCubit!.setRecipientNote('Ua', 'ты же хотел');

      final handoff = composer.fullFormHandoff();

      expect(handoff, isNotNull);
      expect(handoff!.draftId, 'server-beacon');
      expect(handoff.recipientIds, {'Ua', 'Ub', 'Uc'});
      expect(handoff.notes, {'Ua': 'ты же хотел'});
    });

    test(
      'opens BeaconCreateRoute with the same draft id, recipients and notes',
      () async {
        composer.start(BeaconKind.request, Offset.zero);
        await composer.contentChanged();
        await settle();
        composer.forwardCubit!.setRecipientNote('Ua', 'ты же хотел');

        final route = composer.fullFormHandoff()!.toRoute();

        expect(route, isA<BeaconCreateRoute>());
        final args = route.args! as BeaconCreateRouteArgs;
        expect(args.draftId, 'server-beacon');
        expect(args.initialRecipientIds, {'Ua', 'Ub', 'Uc'});
        expect(args.initialNotes, {'Ua': 'ты же хотел'});
      },
    );

    test('is unavailable before the server draft exists', () {
      composer.start(BeaconKind.request, Offset.zero);

      expect(composer.fullFormHandoff(), isNull);
    });
  });

  group('ForwardCubit initial notes', () {
    test('seeds per-recipient notes for the initially selected ids', () async {
      final forward = ForwardCubit(
        beaconId: 'b',
        embedded: true,
        effects: effects,
        debugSkipInitialLoad: true,
        initialSelectedIds: const {'Ua'},
        initialNotes: const {'Ua': 'ты же хотел'},
      );
      addTearDown(forward.close);

      expect(forward.state.perRecipientNotes, {'Ua': 'ты же хотел'});
    });
  });
}
